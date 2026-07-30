import Combine
import MediaPlayer
import MusicKit
import SwiftUI
import UIKit

struct ToastMessage: Identifiable, Equatable {
    enum Style: Equatable {
        case addSuccess
        case keepSuccess
        case deleteSuccess
        case failure
        case neutral
    }

    let id = UUID()
    let title: String
    let subtitle: String?
    let style: Style
}

struct DisplayTrackInfo: Equatable {
    let title: String
    let artist: String
    let albumTitle: String?
    let progress: Double
    let elapsedTime: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
    let helperText: String
    let isDimmed: Bool
    let showsSpinner: Bool
}

struct ResolvedTrackContext: Sendable {
    let verifiedTrack: VerifiedTrack
    let song: Song?
    let membership: MembershipState
    let isInLibrary: Bool
    let resolutionNote: String?
}

private struct PlayerObservation {
    let snapshot: ObservedTrack
    let artwork: UIImage?
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var verificationSurface: VerificationSurface = .unavailable(lastConfirmed: nil)
    @Published private(set) var resolvedContext: ResolvedTrackContext?
    @Published private(set) var permissionStatus: MusicAuthorization.Status = MusicAuthorization.currentStatus
    @Published var autoSkipEnabled: Bool
    @Published var showOnboarding: Bool
    @Published var showDebugOverlay = false
    @Published var toast: ToastMessage?
    @Published var emphasizedAction: TrackActionKind?
    @Published var flashAction: TrackActionKind?
    @Published private(set) var activeActionCount = 0
    @Published private(set) var isSplashVisible = true

    private let player = MPMusicPlayerController.systemMusicPlayer
    private let service: MusicTriageService
    private let defaults: UserDefaults
    private var verificationEngine = PlaybackVerificationEngine()
    private var notificationTokens: [NSObjectProtocol] = []
    private var progressTimer: AnyCancellable?
    private var resolutionTask: Task<Void, Never>?
    private var resolutionIdentity: TrackIdentity?
    private var resolutionAuthorizationStatus: MusicAuthorization.Status?
    private var resolutionRequestToken = UUID()
    private var tagCoordinator = TagOperationCoordinator()
    private var tagOperationTask: Task<Void, Never>?
    private var autoSkipTask: Task<Void, Never>?
    private var autoSkipToken: UUID?
    private var hideToastTask: Task<Void, Never>?
    private var hidePulseTask: Task<Void, Never>?
    private var hideFlashTask: Task<Void, Never>?
    private var hideSplashTask: Task<Void, Never>?
    private var toastPresentationToken = UUID()
    private var pulsePresentationToken = UUID()
    private var flashPresentationToken = UUID()
    private var cooldownUntil: Date?
    private var hasStarted = false
    private var currentObservation: PlayerObservation?
    private var currentArtwork: UIImage?
    private var lastConfirmedArtwork: UIImage?
    private var sceneIsActive = false

    static let onboardingKey = "onboarding-shown"
    static let autoSkipKey = "auto-skip-enabled"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.service = MusicTriageService()
        self.autoSkipEnabled = defaults.object(forKey: Self.autoSkipKey) as? Bool ?? false
        self.showOnboarding = !defaults.bool(forKey: Self.onboardingKey)
    }

    isolated deinit {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        player.endGeneratingPlaybackNotifications()
        progressTimer?.cancel()
        resolutionTask?.cancel()
        tagOperationTask?.cancel()
        autoSkipTask?.cancel()
        hideToastTask?.cancel()
        hidePulseTask?.cancel()
        hideFlashTask?.cancel()
        hideSplashTask?.cancel()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        player.beginGeneratingPlaybackNotifications()

        let center = NotificationCenter.default
        notificationTokens = [
            center.addObserver(
                forName: .MPMusicPlayerControllerNowPlayingItemDidChange,
                object: player,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshPlaybackObservation()
                }
            },
            center.addObserver(
                forName: .MPMusicPlayerControllerPlaybackStateDidChange,
                object: player,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshPlaybackObservation()
                }
            }
        ]

        progressTimer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshPlaybackObservation()
                }
            }

        hideSplashTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(1.5))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.isSplashVisible = false
            }
        }

        refreshPlaybackObservation()
        handleScenePhase(.active)
    }

    func handleScenePhase(_ phase: ScenePhase) {
        sceneIsActive = phase == .active
        if phase == .active {
            refreshAuthorizationStatusOnActivation()
        } else {
            cancelAutoSkip()
        }
        updateIdleTimer()
    }

    var displayTrackInfo: DisplayTrackInfo? {
        switch verificationSurface {
        case .ready(let verified):
            return DisplayTrackInfo(
                title: verified.observation.title,
                artist: verified.observation.artist,
                albumTitle: verified.observation.albumTitle,
                progress: verified.observation.progressFraction,
                elapsedTime: verified.observation.elapsedTime,
                duration: verified.observation.duration,
                isPlaying: verified.observation.isPlaying,
                helperText: helperText(for: verificationSurface, resolutionNote: resolvedContext?.resolutionNote),
                isDimmed: false,
                showsSpinner: false
            )
        case .verifying(let observed, _, _):
            return DisplayTrackInfo(
                title: observed.title,
                artist: observed.artist,
                albumTitle: observed.albumTitle,
                progress: observed.progressFraction,
                elapsedTime: observed.elapsedTime,
                duration: observed.duration,
                isPlaying: observed.isPlaying,
                helperText: helperText(for: verificationSurface, resolutionNote: nil),
                isDimmed: false,
                showsSpinner: true
            )
        case .ambiguous(let observed, let reason, _):
            return DisplayTrackInfo(
                title: observed.title.isEmpty ? "Unknown Song" : observed.title,
                artist: observed.artist.isEmpty ? "Unknown Artist" : observed.artist,
                albumTitle: observed.albumTitle,
                progress: observed.progressFraction,
                elapsedTime: observed.elapsedTime,
                duration: observed.duration,
                isPlaying: observed.isPlaying,
                helperText: reason,
                isDimmed: false,
                showsSpinner: false
            )
        case .unavailable(let lastConfirmed):
            guard let lastConfirmed else { return nil }
            return DisplayTrackInfo(
                title: lastConfirmed.observation.title,
                artist: lastConfirmed.observation.artist,
                albumTitle: lastConfirmed.observation.albumTitle,
                progress: lastConfirmed.observation.progressFraction,
                elapsedTime: lastConfirmed.observation.elapsedTime,
                duration: lastConfirmed.observation.duration,
                isPlaying: false,
                helperText: "Playback disappeared for a moment. Holding the last confirmed song.",
                isDimmed: true,
                showsSpinner: true
            )
        }
    }

    var displayedArtwork: UIImage? {
        switch verificationSurface {
        case .ready, .verifying, .ambiguous:
            currentArtwork ?? lastConfirmedArtwork
        case .unavailable:
            lastConfirmedArtwork
        }
    }

    var currentMembership: MembershipState {
        resolvedContext?.membership ?? .unsorted
    }

    var canShowPermissionRecovery: Bool {
        permissionStatus == .denied || permissionStatus == .restricted
    }

    var permissionRecoveryMessage: String {
        switch permissionStatus {
        case .denied:
            "Apple Music access is off. Music Triage can still show the song, but it cannot tag anything until you re-enable access in Settings."
        case .restricted:
            "This device cannot grant Apple Music access for the app right now."
        default:
            ""
        }
    }

    func dismissOnboarding() {
        showOnboarding = false
        defaults.set(true, forKey: Self.onboardingKey)
    }

    func setAutoSkipEnabled(_ enabled: Bool) {
        autoSkipEnabled = enabled
        defaults.set(enabled, forKey: Self.autoSkipKey)
        if !enabled {
            cancelAutoSkip()
        }
    }

    func toggleDebugOverlay() {
        showDebugOverlay.toggle()
    }

    func closeDebugOverlay() {
        showDebugOverlay = false
    }

    var primaryActionKind: TrackActionKind {
        guard
            case .ready(let verified) = verificationSurface,
            let resolvedContext,
            resolvedContext.verifiedTrack.identity == verified.identity,
            resolvedContext.song != nil,
            !resolvedContext.isInLibrary
        else {
            return .keep
        }

        return .add
    }

    var primaryActionTitle: String {
        primaryActionKind.displayLabel
    }

    var primaryActionSubtitle: String {
        switch primaryActionKind {
        case .add:
            "Library only"
        case .keep:
            "Keepers + library"
        case .delete:
            "Send to triage"
        }
    }

    func canTrigger(_ action: TrackActionKind) -> Bool {
        guard displayTrackInfo != nil else { return false }
        guard !tagCoordinator.isBusy else { return false }
        if canShowPermissionRecovery { return false }
        if let cooldownUntil, cooldownUntil > .now { return false }

        switch verificationSurface {
        case .ready(let verified):
            if permissionStatus == .authorized {
                guard let resolvedContext, resolvedContext.verifiedTrack.identity == verified.identity else {
                    return false
                }
                guard resolvedContext.song != nil else {
                    return false
                }

                switch action {
                case .add:
                    return !resolvedContext.isInLibrary
                case .keep:
                    return true
                case .delete:
                    return resolvedContext.isInLibrary
                }
            }
            return permissionStatus == .notDetermined
        default:
            return false
        }
    }

    func isMatchingMembership(_ action: TrackActionKind) -> Bool {
        switch action {
        case .add:
            false
        case .keep:
            currentMembership.isKeeper
        case .delete:
            currentMembership.isTriaged
        }
    }

    func handlePrimaryAction(_ action: TrackActionKind) {
        guard
            canTrigger(action),
            case .ready(let verifiedTrack) = verificationSurface,
            let operation = tagCoordinator.begin(action: action, identity: verifiedTrack.identity)
        else {
            return
        }

        cancelAutoSkip()
        activeActionCount = 1
        tagOperationTask = Task { [weak self, operation] in
            await self?.performPrimaryAction(operation)
        }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func playPause() {
        cancelAutoSkip()
        if player.playbackState == .playing {
            player.pause()
        } else {
            player.play()
        }
        refreshPlaybackObservation()
    }

    func skipNext() {
        cancelAutoSkip()
        player.skipToNextItem()
        refreshPlaybackObservation()
    }

    func skipPrevious() {
        cancelAutoSkip()
        player.skipToPreviousItem()
        refreshPlaybackObservation()
    }

    func seek(to progress: Double) {
        cancelAutoSkip()
        guard let currentObservation else { return }
        let duration = currentObservation.snapshot.duration
        guard duration.isFinite, duration > 0 else { return }

        let clampedProgress = min(max(progress, 0), 1)
        player.currentPlaybackTime = duration * clampedProgress
        refreshPlaybackObservation()
    }

    var debugLines: [String] {
        var lines: [String] = []
        lines.append("Permission: \(permissionStatus)")
        lines.append("Playback state: \(player.playbackState.debugLabel)")
        if let observation = currentObservation?.snapshot {
            lines.append("Title: \(observation.title)")
            lines.append("Artist: \(observation.artist)")
            lines.append("Store ID: \(observation.playbackStoreID ?? "none")")
            lines.append("Persistent ID: \(observation.persistentID.map(String.init) ?? "none")")
        }
        if let resolvedContext {
            lines.append("Resolved song: \(resolvedContext.song?.title ?? "none")")
            lines.append("Library: \(resolvedContext.isInLibrary)")
            lines.append("KEEPER: \(resolvedContext.membership.isKeeper)")
            lines.append("TRIAGED: \(resolvedContext.membership.isTriaged)")
            if let resolutionNote = resolvedContext.resolutionNote {
                lines.append("Note: \(resolutionNote)")
            }
        }
        return lines
    }

    private func refreshPlaybackObservation() {
        let now = Date()
        guard let item = player.nowPlayingItem else {
            cancelAutoSkip()
            invalidateResolution()
            currentObservation = nil
            currentArtwork = nil
            verificationSurface = verificationEngine.process(snapshot: nil, now: now)
            preserveContextForUnavailableState()
            updateIdleTimer()
            return
        }

        let snapshot = ObservedTrack(
            title: item.title ?? "Unknown Song",
            artist: item.artist ?? "Unknown Artist",
            albumTitle: item.albumTitle,
            playbackStoreID: item.playbackStoreID,
            persistentID: item.persistentID == 0 ? nil : item.persistentID,
            duration: item.playbackDuration,
            elapsedTime: player.currentPlaybackTime,
            playbackStateDescription: player.playbackState.debugLabel,
            isPlaying: player.playbackState == .playing,
            capturedAt: now
        )

        if let previous = currentObservation?.snapshot,
           previous.derivedIdentity != snapshot.derivedIdentity
            || previous.metadataSignature != snapshot.metadataSignature
            || previous.isPlaying != snapshot.isPlaying {
            cancelAutoSkip()
            invalidateResolution()
        }

        let artwork = item.artwork?.image(at: CGSize(width: 900, height: 900))
        currentObservation = PlayerObservation(snapshot: snapshot, artwork: artwork)
        currentArtwork = artwork

        let nextSurface = verificationEngine.process(snapshot: snapshot, now: now)
        verificationSurface = nextSurface

        if case .ready = nextSurface {
            lastConfirmedArtwork = artwork ?? lastConfirmedArtwork
        }

        switch nextSurface {
        case .ready(let verified):
            refreshResolvedContext(for: verified)
        case .unavailable(let lastConfirmed):
            preserveContextForUnavailableState(lastConfirmed: lastConfirmed)
        case .verifying(let observed, _, _), .ambiguous(let observed, _, _):
            if resolvedContext?.verifiedTrack.identity != observed.derivedIdentity
                || resolvedContext?.verifiedTrack.observation.metadataSignature != observed.metadataSignature {
                resolvedContext = nil
            }
        }

        updateIdleTimer()
    }

    private func refreshResolvedContext(for verified: VerifiedTrack, force: Bool = false) {
        if let resolvedContext,
           resolvedContext.verifiedTrack.identity == verified.identity,
           resolvedContext.verifiedTrack.observation.metadataSignature == verified.observation.metadataSignature {
            if resolvedContext.song != nil {
                self.resolvedContext = ResolvedTrackContext(
                    verifiedTrack: verified,
                    song: resolvedContext.song,
                    membership: resolvedContext.membership,
                    isInLibrary: resolvedContext.isInLibrary,
                    resolutionNote: resolvedContext.resolutionNote
                )
                return
            }
        } else if resolvedContext != nil {
            self.resolvedContext = nil
        }

        let authorizationStatus = MusicAuthorization.currentStatus
        guard force
            || resolutionIdentity != verified.identity
            || resolutionAuthorizationStatus != authorizationStatus
        else {
            return
        }

        resolutionTask?.cancel()
        let token = UUID()
        resolutionRequestToken = token
        resolutionIdentity = verified.identity
        resolutionAuthorizationStatus = authorizationStatus
        resolutionTask = Task { [weak self, service, verified, authorizationStatus] in
            do {
                try Task.checkCancellation()
                let context = try await service.resolveContext(
                    for: verified,
                    authorizationStatus: authorizationStatus
                )
                try Task.checkCancellation()
                await MainActor.run { [weak self] in
                    guard let self,
                          !Task.isCancelled,
                          self.resolutionRequestToken == token,
                          case .ready(let currentVerified) = self.verificationSurface,
                          currentVerified.identity == verified.identity
                    else {
                        return
                    }

                    self.resolvedContext = context
                    self.resolutionTask = nil
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.resolutionRequestToken == token else { return }
                    self.resolutionTask = nil
                }
            }
        }
    }

    private func invalidateResolution() {
        resolutionTask?.cancel()
        resolutionTask = nil
        resolutionIdentity = nil
        resolutionAuthorizationStatus = nil
        resolutionRequestToken = UUID()
    }

    private func preserveContextForUnavailableState(lastConfirmed: VerifiedTrack? = nil) {
        guard
            let lastConfirmed = lastConfirmed ?? verificationEngine.confirmedTrack,
            resolvedContext?.verifiedTrack.identity == lastConfirmed.identity
        else {
            return
        }

        resolvedContext = ResolvedTrackContext(
            verifiedTrack: lastConfirmed,
            song: resolvedContext?.song,
            membership: resolvedContext?.membership ?? .unsorted,
            isInLibrary: resolvedContext?.isInLibrary ?? false,
            resolutionNote: resolvedContext?.resolutionNote
        )
    }

    private func performPrimaryAction(_ operation: TagOperationCoordinator.Operation) async {
        defer {
            finishTagOperation(operation)
        }

        guard isCurrentTagOperation(operation) else { return }
        guard await ensureAuthorizationForAction(for: operation) else { return }
        guard isCurrentTagOperation(operation) else { return }
        guard let resolvedContext,
              resolvedContext.verifiedTrack.identity == operation.identity,
              resolvedContext.song != nil else {
            presentToast(
                title: "Song lookup still finishing",
                subtitle: "Hold again once Music Triage enables the action.",
                style: .neutral
            )
            return
        }

        if isMatchingMembership(operation.action, membership: resolvedContext.membership) {
            presentToast(
                title: "\(operation.action.displayLabel) reconfirmed",
                subtitle: "Already tagged for \(resolvedContext.verifiedTrack.observation.title).",
                style: .neutral
            )
            pulse(operation.action)
            notifySuccess(for: operation.action)
            return
        }

        let trackTitle = resolvedContext.verifiedTrack.observation.title

        do {
            let outcome = try await service.perform(operation.action, on: resolvedContext)
            guard !Task.isCancelled, isCurrentTagOperation(operation) else { return }

            cooldownUntil = Date().addingTimeInterval(1)
            if self.resolvedContext?.verifiedTrack.identity == resolvedContext.verifiedTrack.identity {
                self.resolvedContext = ResolvedTrackContext(
                    verifiedTrack: resolvedContext.verifiedTrack,
                    song: resolvedContext.song,
                    membership: outcome.membershipState,
                    isInLibrary: outcome.libraryAdded || resolvedContext.isInLibrary,
                    resolutionNote: nil
                )
            }

            let subtitle = outcome.warnings.first
            presentToast(
                title: "\(operation.action.displayLabel) saved",
                subtitle: subtitle,
                style: toastStyle(for: operation.action)
            )
            triggerFlash(for: operation.action)
            pulse(operation.action)
            notifySuccess(for: operation.action)

            if autoSkipEnabled {
                scheduleAutoSkip(for: operation, identity: resolvedContext.verifiedTrack.identity)
            }
        } catch {
            guard !Task.isCancelled, isCurrentTagOperation(operation) else { return }
            presentToast(
                title: "\(operation.action.displayLabel) failed for \(trackTitle)",
                subtitle: error.localizedDescription,
                style: .failure
            )
            notifyFailure()
        }
    }

    private func finishTagOperation(_ operation: TagOperationCoordinator.Operation) {
        guard tagCoordinator.finish(operation) else { return }
        activeActionCount = 0
        tagOperationTask = nil
    }

    private func isCurrentTagOperation(_ operation: TagOperationCoordinator.Operation) -> Bool {
        guard
            tagCoordinator.owns(operation),
            case .ready(let verifiedTrack) = verificationSurface
        else {
            return false
        }

        return tagCoordinator.owns(operation, for: verifiedTrack.identity)
    }

    private func isMatchingMembership(
        _ action: TrackActionKind,
        membership: MembershipState
    ) -> Bool {
        switch action {
        case .add:
            false
        case .keep:
            membership.isKeeper
        case .delete:
            membership.isTriaged
        }
    }

    private func ensureAuthorizationForAction(
        for operation: TagOperationCoordinator.Operation
    ) async -> Bool {
        guard isCurrentTagOperation(operation) else { return false }

        permissionStatus = MusicAuthorization.currentStatus
        switch permissionStatus {
        case .authorized:
            return true
        case .notDetermined:
            let status = await service.requestAuthorization()
            guard isCurrentTagOperation(operation) else { return false }
            permissionStatus = status
            if status == .authorized {
                guard case .ready(let verifiedTrack) = verificationSurface else { return false }
                resolvedContext = nil
                invalidateResolution()
                refreshResolvedContext(for: verifiedTrack, force: true)
                presentToast(
                    title: "Apple Music access enabled",
                    subtitle: "Hold again once the song lookup finishes.",
                    style: .neutral
                )
            }
            return false
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func refreshAuthorizationStatusOnActivation() {
        let latestStatus = MusicAuthorization.currentStatus
        let statusChanged = permissionStatus != latestStatus
        permissionStatus = latestStatus

        guard statusChanged else { return }

        invalidateResolution()
        guard case .ready(let verifiedTrack) = verificationSurface else {
            resolvedContext = nil
            return
        }

        resolvedContext = nil
        if latestStatus == .authorized {
            refreshResolvedContext(for: verifiedTrack, force: true)
        }
    }

    private func scheduleAutoSkip(
        for operation: TagOperationCoordinator.Operation,
        identity: TrackIdentity
    ) {
        guard sceneIsActive else { return }
        cancelAutoSkip()
        autoSkipToken = operation.token
        autoSkipTask = Task { [weak self, operation, identity] in
            do {
                try await Task.sleep(for: .milliseconds(650))
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                self?.completeAutoSkip(for: operation.token, identity: identity)
            }
        }
    }

    private func completeAutoSkip(for token: UUID, identity: TrackIdentity) {
        guard autoSkipToken == token, sceneIsActive else {
            autoSkipTask = nil
            autoSkipToken = nil
            return
        }

        // Re-sample the player immediately before acting so a delayed or
        // missing notification cannot make this task skip a newer song.
        refreshPlaybackObservation()
        guard
            autoSkipToken == token,
            sceneIsActive,
            case .ready(let verifiedTrack) = verificationSurface,
            verifiedTrack.identity == identity
        else {
            autoSkipTask = nil
            autoSkipToken = nil
            return
        }

        autoSkipTask = nil
        autoSkipToken = nil
        player.skipToNextItem()
        refreshPlaybackObservation()
    }

    private func cancelAutoSkip() {
        autoSkipTask?.cancel()
        autoSkipTask = nil
        autoSkipToken = nil
    }

    private func helperText(for surface: VerificationSurface, resolutionNote: String?) -> String {
        if tagCoordinator.isBusy {
            return "Saving this tag. Actions are temporarily disabled."
        }

        if let resolutionNote, !resolutionNote.isEmpty {
            return resolutionNote
        }

        switch surface {
        case .ready(let verified):
            if let resolvedContext, resolvedContext.verifiedTrack.identity == verified.identity, resolvedContext.song == nil {
                return resolvedContext.resolutionNote ?? "Verified playback. Finishing the song lookup before enabling actions."
            }
            if resolvedContext == nil {
                return "Verified playback. Finishing the song lookup before enabling actions."
            }
            if let resolvedContext,
               resolvedContext.verifiedTrack.identity == verified.identity,
               resolvedContext.song != nil,
               !resolvedContext.isInLibrary {
                return "Verified Apple Music track. ADD can put it in your library; DELETE stays off until it is already in your library."
            }
            if verified.identity.strength == .fallback {
                return "Verified cautiously from stable title and artist."
            }
            return verified.observation.isPlaying
                ? "Verified. Actions are safe for this song."
                : "Verified. Still safe to tag while paused."
        case .verifying:
            return "Verifying the song before enabling KEEP and DELETE."
        case .ambiguous(_, let reason, _):
            return reason
        case .unavailable:
            return "Playback disappeared for a moment. Holding the last confirmed song."
        }
    }

    private func pulse(_ action: TrackActionKind) {
        let token = UUID()
        pulsePresentationToken = token
        hidePulseTask?.cancel()
        emphasizedAction = action
        hidePulseTask = Task { [weak self, token] in
            do {
                try await Task.sleep(for: .milliseconds(900))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard self?.pulsePresentationToken == token else { return }
                self?.emphasizedAction = nil
            }
        }
    }

    private func triggerFlash(for action: TrackActionKind) {
        let token = UUID()
        flashPresentationToken = token
        hideFlashTask?.cancel()
        flashAction = action
        hideFlashTask = Task { [weak self, token] in
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard self?.flashPresentationToken == token else { return }
                self?.flashAction = nil
            }
        }
    }

    private func presentToast(title: String, subtitle: String?, style: ToastMessage.Style) {
        let token = UUID()
        toastPresentationToken = token
        hideToastTask?.cancel()
        toast = ToastMessage(title: title, subtitle: subtitle, style: style)
        hideToastTask = Task { [weak self, token] in
            do {
                try await Task.sleep(for: .seconds(2.4))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard self?.toastPresentationToken == token else { return }
                self?.toast = nil
            }
        }
    }

    private func toastStyle(for action: TrackActionKind) -> ToastMessage.Style {
        switch action {
        case .add:
            .addSuccess
        case .keep:
            .keepSuccess
        case .delete:
            .deleteSuccess
        }
    }

    private func notifySuccess(for action: TrackActionKind) {
        let impact = UIImpactFeedbackGenerator(style: action == .delete ? .rigid : .heavy)
        impact.prepare()
        impact.impactOccurred(intensity: 1)

        let notification = UINotificationFeedbackGenerator()
        notification.prepare()
        switch action {
        case .add:
            notification.notificationOccurred(.success)
        case .keep:
            notification.notificationOccurred(.success)
        case .delete:
            notification.notificationOccurred(.warning)
        }
    }

    private func notifyFailure() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    private func updateIdleTimer() {
        let shouldStayAwake = sceneIsActive && currentObservation?.snapshot.isPlaying == true
        UIApplication.shared.isIdleTimerDisabled = shouldStayAwake
    }
}

private extension MPMusicPlaybackState {
    var debugLabel: String {
        switch self {
        case .stopped:
            "stopped"
        case .playing:
            "playing"
        case .paused:
            "paused"
        case .interrupted:
            "interrupted"
        case .seekingForward:
            "seeking-forward"
        case .seekingBackward:
            "seeking-backward"
        @unknown default:
            "unknown"
        }
    }
}
