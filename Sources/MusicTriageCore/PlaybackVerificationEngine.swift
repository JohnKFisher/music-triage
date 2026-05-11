import Foundation

public struct PlaybackVerificationEngine: Sendable {
    public var strongIdentityStabilityWindow: TimeInterval
    public var fallbackStabilityWindow: TimeInterval

    private var candidateIdentity: TrackIdentity?
    private var candidateMetadataSignature: String?
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

        if let lastConfirmed, lastConfirmed.identity == identity, lastConfirmed.observation.metadataSignature == snapshot.metadataSignature {
            self.lastConfirmed = VerifiedTrack(identity: identity, observation: snapshot, confirmedAt: lastConfirmed.confirmedAt)
            return .ready(self.lastConfirmed!)
        }

        let signature = snapshot.metadataSignature
        let isSameCandidate = candidateIdentity == identity && candidateMetadataSignature == signature

        if !isSameCandidate {
            candidateIdentity = identity
            candidateMetadataSignature = signature
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
        candidateIdentity = nil
        candidateMetadataSignature = nil
        candidateSince = nil
    }
}
