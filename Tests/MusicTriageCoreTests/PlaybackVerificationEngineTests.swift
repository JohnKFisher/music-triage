import Foundation
import Testing
@testable import MusicTriageCore

struct PlaybackVerificationEngineTests {
    @Test
    func strongIdentityConfirmsAfterOneSecond() {
        var engine = PlaybackVerificationEngine()
        let start = Date(timeIntervalSinceReferenceDate: 100)
        let observed = makeTrack(playbackStoreID: "12345", capturedAt: start)

        let first = engine.process(snapshot: observed, now: start)
        #expect(first == .verifying(observed: observed, candidateSince: start, lastConfirmed: nil))

        let second = engine.process(snapshot: observed, now: start.addingTimeInterval(1.05))
        guard case let .ready(verified) = second else {
            Issue.record("Expected ready state for strong identifier.")
            return
        }

        #expect(verified.identity.strength == .strong)
        #expect(verified.observation.title == observed.title)
    }

    @Test
    func fallbackIdentityWaitsTwoSeconds() {
        var engine = PlaybackVerificationEngine()
        let start = Date(timeIntervalSinceReferenceDate: 200)
        let observed = makeTrack(playbackStoreID: nil, persistentID: nil, capturedAt: start)

        let first = engine.process(snapshot: observed, now: start)
        #expect(first == .verifying(observed: observed, candidateSince: start, lastConfirmed: nil))

        let second = engine.process(snapshot: observed, now: start.addingTimeInterval(1.5))
        #expect(second == .verifying(observed: observed, candidateSince: start, lastConfirmed: nil))

        let third = engine.process(snapshot: observed, now: start.addingTimeInterval(2.1))
        guard case let .ready(verified) = third else {
            Issue.record("Expected ready state for fallback identifier.")
            return
        }

        #expect(verified.identity.strength == .fallback)
    }

    @Test
    func changeResetsCandidateAndPreservesLastConfirmed() {
        var engine = PlaybackVerificationEngine()
        let start = Date(timeIntervalSinceReferenceDate: 300)
        let firstTrack = makeTrack(playbackStoreID: "abc", capturedAt: start)
        _ = engine.process(snapshot: firstTrack, now: start)
        let ready = engine.process(snapshot: firstTrack, now: start.addingTimeInterval(1.1))

        guard case .ready = ready else {
            Issue.record("Expected first track to be ready.")
            return
        }

        let secondTrack = makeTrack(title: "Other Song", artist: "Other Artist", playbackStoreID: "xyz", capturedAt: start.addingTimeInterval(1.2))
        let verifying = engine.process(snapshot: secondTrack, now: start.addingTimeInterval(1.2))

        guard case let .verifying(observed, _, lastConfirmed) = verifying else {
            Issue.record("Expected changed song to return to verifying.")
            return
        }

        #expect(observed.title == "Other Song")
        #expect(lastConfirmed?.observation.title == firstTrack.title)
    }

    @Test
    func missingPlaybackShowsUnavailableAndKeepsLastConfirmed() {
        var engine = PlaybackVerificationEngine()
        let start = Date(timeIntervalSinceReferenceDate: 400)
        let observed = makeTrack(playbackStoreID: "stable", capturedAt: start)

        _ = engine.process(snapshot: observed, now: start)
        _ = engine.process(snapshot: observed, now: start.addingTimeInterval(1.05))

        let unavailable = engine.process(snapshot: nil, now: start.addingTimeInterval(1.2))
        guard case let .unavailable(lastConfirmed) = unavailable else {
            Issue.record("Expected unavailable state.")
            return
        }

        #expect(lastConfirmed?.observation.title == observed.title)
    }

    private func makeTrack(
        title: String = "Fast Car",
        artist: String = "Tracey Chapman",
        albumTitle: String? = "Fast Car",
        playbackStoreID: String?,
        persistentID: UInt64? = 42,
        capturedAt: Date
    ) -> ObservedTrack {
        ObservedTrack(
            title: title,
            artist: artist,
            albumTitle: albumTitle,
            playbackStoreID: playbackStoreID,
            persistentID: persistentID,
            duration: 280,
            elapsedTime: 12,
            playbackStateDescription: "playing",
            isPlaying: true,
            capturedAt: capturedAt
        )
    }
}
