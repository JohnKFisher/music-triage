import CarPlay
import Combine
import UIKit

@MainActor
final class MusicTriageApplicationDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if connectingSceneSession.role == .carTemplateApplication {
            let configuration = UISceneConfiguration(
                name: "Music Triage CarPlay",
                sessionRole: connectingSceneSession.role
            )
            configuration.sceneClass = CPTemplateApplicationScene.self
            configuration.delegateClass = CarPlaySceneDelegate.self
            return configuration
        }

        return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    }
}

@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private struct PendingConfirmation {
        let action: TrackActionKind
        let reference: TrackReference
    }

    private let model = AppModel.shared
    private var interfaceController: CPInterfaceController?
    private var listTemplate: CPListTemplate?
    private var modelObservation: AnyCancellable?
    private var lastScreenState: CarPlayScreenState?
    private var pendingConfirmation: PendingConfirmation?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        model.start()

        let initialState = model.carPlayScreenState
        let template = makeListTemplate(for: initialState)
        listTemplate = template
        lastScreenState = initialState
        interfaceController.setRootTemplate(template, animated: false, completion: nil)

        modelObservation = model.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshTemplateIfNeeded()
            }
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        guard self.interfaceController === interfaceController else { return }
        disconnect()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        model.handleCarPlaySceneActive(true)
    }

    func sceneWillResignActive(_ scene: UIScene) {
        model.handleCarPlaySceneActive(false)
    }

    private func disconnect() {
        model.handleCarPlaySceneActive(false)
        modelObservation?.cancel()
        modelObservation = nil
        pendingConfirmation = nil
        listTemplate = nil
        lastScreenState = nil
        interfaceController = nil
    }

    private func refreshTemplateIfNeeded() {
        guard let listTemplate else { return }
        let state = model.carPlayScreenState
        guard state != lastScreenState else { return }

        if let pendingConfirmation, !canConfirm(pendingConfirmation, with: state) {
            self.pendingConfirmation = nil
            if interfaceController?.presentedTemplate is CPAlertTemplate {
                interfaceController?.dismissTemplate(animated: true, completion: nil)
            }
        }

        lastScreenState = state
        listTemplate.updateSections(makeSections(for: state))
    }

    private func makeListTemplate(for state: CarPlayScreenState) -> CPListTemplate {
        CPListTemplate(title: "Music Triage", sections: makeSections(for: state))
    }

    private func makeSections(for state: CarPlayScreenState) -> [CPListSection] {
        let trackItem = CPListItem(text: state.title, detailText: state.artist)
        trackItem.isEnabled = false

        let statusItem = CPListItem(text: state.status, detailText: state.membership)
        statusItem.isEnabled = false

        var nowPlayingItems = [trackItem, statusItem]
        if let feedback = state.feedback {
            let feedbackItem = CPListItem(text: feedback, detailText: nil)
            feedbackItem.isEnabled = false
            nowPlayingItems.append(feedbackItem)
        }

        let primaryItem = makeActionItem(
            title: state.primaryActionTitle,
            detail: state.primaryActionDetail,
            action: state.primaryAction,
            reference: state.reference,
            isEnabled: state.canTriggerPrimaryAction
        )
        let triageItem = makeActionItem(
            title: "TRIAGE",
            detail: "Send to Music Triage playlist",
            action: .delete,
            reference: state.reference,
            isEnabled: state.canTriggerTriageAction
        )

        var sections = [
            CPListSection(items: nowPlayingItems),
            CPListSection(items: [primaryItem, triageItem])
        ]

        if state.hasPlaybackControls {
            sections.append(playbackSection(for: state))
        }

        return sections
    }

    private func makeActionItem(
        title: String,
        detail: String,
        action: TrackActionKind?,
        reference: TrackReference?,
        isEnabled: Bool
    ) -> CPListItem {
        let item = CPListItem(text: title, detailText: detail)
        item.isEnabled = isEnabled && action != nil && reference != nil
        item.handler = { [weak self] _, completion in
            defer { completion() }
            guard let self, let action, let reference,
                  self.model.canTriggerCarPlay(action, expectedReference: reference)
            else {
                self?.refreshTemplateIfNeeded()
                return
            }

            let currentState = self.model.carPlayScreenState
            guard currentState.reference == reference else {
                self.refreshTemplateIfNeeded()
                return
            }
            self.presentConfirmation(
                for: action,
                trackTitle: currentState.title,
                artist: currentState.artist,
                reference: reference
            )
        }
        return item
    }

    private func playbackSection(for state: CarPlayScreenState) -> CPListSection {
        let previous = CPListItem(text: "Previous", detailText: nil)
        previous.handler = { [weak self] _, completion in
            self?.model.skipPrevious()
            completion()
        }

        let playPause = CPListItem(text: state.isPlaying ? "Pause" : "Play", detailText: nil)
        playPause.handler = { [weak self] _, completion in
            self?.model.playPause()
            completion()
        }

        let next = CPListItem(text: "Next", detailText: nil)
        next.handler = { [weak self] _, completion in
            self?.model.skipNext()
            completion()
        }

        return CPListSection(items: [previous, playPause, next])
    }

    private func presentConfirmation(
        for action: TrackActionKind,
        trackTitle: String,
        artist: String,
        reference: TrackReference
    ) {
        guard let interfaceController, interfaceController.presentedTemplate == nil else { return }

        let actionTitle = confirmationActionTitle(for: action)
        let titleVariants = confirmationTitleVariants(for: action, trackTitle: trackTitle, artist: artist)
        let confirm = CPAlertAction(title: actionTitle, style: .default) { [weak self] _ in
            guard let self else { return }
            self.pendingConfirmation = nil
            _ = self.model.handlePrimaryAction(
                action,
                source: .carPlay,
                expectedReference: reference
            )
            self.refreshTemplateIfNeeded()
        }
        let cancel = CPAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.pendingConfirmation = nil
        }
        let alert = CPAlertTemplate(titleVariants: titleVariants, actions: [confirm, cancel])
        pendingConfirmation = PendingConfirmation(action: action, reference: reference)
        interfaceController.presentTemplate(alert, animated: true) { [weak self] success, _ in
            if !success {
                self?.pendingConfirmation = nil
            }
        }
    }

    private func canConfirm(_ confirmation: PendingConfirmation, with state: CarPlayScreenState) -> Bool {
        guard state.reference == confirmation.reference else { return false }
        switch confirmation.action {
        case .add, .keep:
            return state.primaryAction == confirmation.action && state.canTriggerPrimaryAction
        case .delete:
            return state.canTriggerTriageAction
        }
    }

    private func confirmationActionTitle(for action: TrackActionKind) -> String {
        switch action {
        case .add:
            "ADD"
        case .keep:
            "KEEP"
        case .delete:
            "TRIAGE"
        }
    }

    private func confirmationTitleVariants(
        for action: TrackActionKind,
        trackTitle: String,
        artist: String
    ) -> [String] {
        let trackAndArtist = artist.isEmpty ? trackTitle : "\(trackTitle) by \(artist)"
        switch action {
        case .add:
            return [
                "Add \(trackAndArtist) to your library?",
                "Add \(trackAndArtist)?"
            ]
        case .keep:
            return [
                "Keep \(trackAndArtist) in Keepers?",
                "Keep \(trackAndArtist)?"
            ]
        case .delete:
            return [
                "Send \(trackAndArtist) to Music Triage?",
                "Triage \(trackAndArtist)?"
            ]
        }
    }
}
