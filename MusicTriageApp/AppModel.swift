import Combine
import MediaPlayer
import MusicKit
import SwiftUI
import UIKit

struct ToastMessage: Identifiable, Equatable {
    enum Style: Equatable {
        case success
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
    @Published private(set) var activeActionCount = 0
    @Published private(set) var isSplashVisible = true

    private let player = MPMusicPlayerController.systemMusicPlayer
    private let service: MusicTriageService
    private let defaults: UserDefaults
    private var verificationEngine = PlaybackVerificationEngine()
    private var notificationTokens: [NSObjectProtocol] = []
    private var progressTimer: AnyCancellable?
    private var resolutionTask: Task<Void, Never>?
    private var hideToastTask: Task<Void, Never>?
    private var hidePulseTask: Task<Void, Never>?
    private var hideSplashTask: Task<Void, Never>?
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
            try? await Task.sleep(for: .milliseconds(850))
            await MainActor.run {
                self?.isSplashVisible = false
            }
        }

        refreshPlaybackObservation()
        handleScenePhase(.active)
    }

    func handleScenePhase(_ phase: ScenePhase) {
        sceneIsActive = phase == .active
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
    }

    func toggleDebugOverlay() {
        showDebugOverlay.toggle()
    }

    func canTrigger(_ action: TrackActionKind) -> Bool {
        guard displayTrackInfo != nil else { return false }
        if canShowPermissionRecovery { return false }
        if let cooldownUntil, cooldownUntil > .now { return false }

        switch verificationSurface {
        case .ready(let verified):
            if permissionStatus == .authorized {
                return resolvedContext?.verifiedTrack.identity == verified.identity
            }
            return permissionStatus == .notDetermined
        default:
            return false
        }
    }

    func isMatchingMembership(_ action: TrackActionKind) -> Bool {
        switch action {
        case .keep:
            currentMembership.isKeeper
        case .delete:
            currentMembership.isTriaged
        }
    }

    func handlePrimaryAction(_ action: TrackActionKind) {
        Task { [weak self] in
            await self?.performPrimaryAction(action)
        }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func playPause() {
        if player.playbackState == .playing {
            player.pause()
        } else {
            player.play()
        }
        refreshPlaybackObservation()
    }

    func skipNext() {
        player.skipToNextItem()
        refreshPlaybackObservation()
    }

    func skipPrevious() {
        player.skipToPreviousItem()
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
            if resolvedContext?.verifiedTrack.identity != observed.derivedIdentity {
                resolvedContext = nil
            }
        }

        updateIdleTimer()
    }

    private func refreshResolvedContext(for verified: VerifiedTrack) {
        if let resolvedContext, resolvedContext.verifiedTrack.identity == verified.identity {
            self.resolvedContext = ResolvedTrackContext(
                verifiedTrack: verified,
                song: resolvedContext.song,
                membership: resolvedContext.membership,
                isInLibrary: resolvedContext.isInLibrary,
                resolutionNote: resolvedContext.resolutionNote
            )
            return
        }

        resolutionTask?.cancel()
        resolutionTask = Task { [service] in
            let context = await service.resolveContext(for: verified, authorizationStatus: MusicAuthorization.currentStatus)
            await MainActor.run {
                guard !Task.isCancelled else { return }
                if case .ready(let currentVerified) = self.verificationSurface, currentVerified.identity == verified.identity {
                    self.resolvedContext = context
                }
            }
        }
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

    private func performPrimaryAction(_ action: TrackActionKind) async {
        let granted = await ensureAuthorizationForAction()
        guard granted else { return }

        guard case .ready(let verifiedTrack) = verificationSurface else { return }

        if resolvedContext?.verifiedTrack.identity != verifiedTrack.identity {
            refreshResolvedContext(for: verifiedTrack)
            try? await Task.sleep(for: .milliseconds(250))
        }

        guard let resolvedContext else {
            presentToast(
                title: "Song not safe to tag yet",
                subtitle: "Music Triage could not resolve this track cleanly enough to write to your library.",
                style: .failure
            )
            notifyFailure()
            return
        }

        if isMatchingMembership(action) {
            presentToast(
                title: "\(action.displayLabel) reconfirmed",
                subtitle: "Already tagged for \(resolvedContext.verifiedTrack.observation.title).",
                style: .neutral
            )
            pulse(action)
            notifySuccess(for: action)
            return
        }

        activeActionCount += 1
        let trackTitle = resolvedContext.verifiedTrack.observation.title

        do {
            let outcome = try await service.perform(action, on: resolvedContext)
            activeActionCount -= 1
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
                title: "\(action.displayLabel) saved",
                subtitle: subtitle,
                style: .success
            )
            pulse(action)
            notifySuccess(for: action)

            if autoSkipEnabled {
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(650))
                    await MainActor.run {
                        self?.player.skipToNextItem()
                        self?.refreshPlaybackObservation()
                    }
                }
            }
        } catch {
            activeActionCount -= 1
            presentToast(
                title: "\(action.displayLabel) failed for \(trackTitle)",
                subtitle: error.localizedDescription,
                style: .failure
            )
            notifyFailure()
        }
    }

    private func ensureAuthorizationForAction() async -> Bool {
        permissionStatus = MusicAuthorization.currentStatus
        switch permissionStatus {
        case .authorized:
            return true
        case .notDetermined:
            let status = await service.requestAuthorization()
            permissionStatus = status
            if status == .authorized {
                if case .ready(let verifiedTrack) = verificationSurface {
                    refreshResolvedContext(for: verifiedTrack)
                }
                return true
            }
            return false
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func helperText(for surface: VerificationSurface, resolutionNote: String?) -> String {
        if let resolutionNote, !resolutionNote.isEmpty {
            return resolutionNote
        }

        switch surface {
        case .ready(let verified):
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
        emphasizedAction = action
        hidePulseTask?.cancel()
        hidePulseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            await MainActor.run {
                self?.emphasizedAction = nil
            }
        }
    }

    private func presentToast(title: String, subtitle: String?, style: ToastMessage.Style) {
        toast = ToastMessage(title: title, subtitle: subtitle, style: style)
        hideToastTask?.cancel()
        hideToastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            await MainActor.run {
                self?.toast = nil
            }
        }
    }

    private func notifySuccess(for action: TrackActionKind) {
        switch action {
        case .keep:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .delete:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
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
