import Foundation

public struct PlaybackVerificationEngine: Sendable {
    public var strongIdentityStabilityWindow: TimeInterval
    public var fallbackStabilityWindow: TimeInterval

    private var candidateFingerprint: TrackFingerprint?
    private var candidateSince: Date?
    private var lastConfirmed: VerifiedTrack?

    public init(
        strongIdentityStabilityWindow: TimeInterval = 1.0,
        fallbackStabilityWindow: TimeInterval = 2.0
    ) {
        self.strongIdentityStabilityWindow = strongIdentityStabilityWindow
        self.fallbackStabilityWindow = fallbackStabilityWindow
    }

    public var confirmedTrack: VerifiedTrack? {
        lastConfirmed
    }

    public mutating func process(snapshot: ObservedTrack?, now: Date = .now) -> VerificationSurface {
        guard let snapshot else {
            clearCandidate()
            return .unavailable(lastConfirmed: lastConfirmed)
        }

        guard let identity = snapshot.derivedIdentity else {
            clearCandidate()
            return .ambiguous(
                observed: snapshot,
                reason: "Waiting for clearer track metadata.",
                lastConfirmed: lastConfirmed
            )
        }

        let fingerprint = TrackFingerprint(identity: identity, observation: snapshot)

        if let lastConfirmed, lastConfirmed.fingerprint == fingerprint {
            clearCandidate()
            self.lastConfirmed = VerifiedTrack(identity: identity, observation: snapshot, confirmedAt: lastConfirmed.confirmedAt)
            return .ready(self.lastConfirmed!)
        }

        let isSameCandidate = candidateFingerprint == fingerprint

        if !isSameCandidate {
            candidateFingerprint = fingerprint
            candidateSince = now
            return .verifying(observed: snapshot, candidateSince: now, lastConfirmed: lastConfirmed)
        }

        let stableFor = now.timeIntervalSince(candidateSince ?? now)
        if stableFor >= stabilityWindow(for: identity) {
            let confirmed = VerifiedTrack(identity: identity, observation: snapshot, confirmedAt: now)
            lastConfirmed = confirmed
            return .ready(confirmed)
        }

        return .verifying(
            observed: snapshot,
            candidateSince: candidateSince ?? now,
            lastConfirmed: lastConfirmed
        )
    }

    private func stabilityWindow(for identity: TrackIdentity) -> TimeInterval {
        switch identity.strength {
        case .strong:
            strongIdentityStabilityWindow
        case .fallback:
            fallbackStabilityWindow
        }
    }

    private mutating func clearCandidate() {
        candidateFingerprint = nil
        candidateSince = nil
    }
}
