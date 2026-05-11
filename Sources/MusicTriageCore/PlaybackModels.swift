import Foundation

public enum LogicalPlaylist: String, CaseIterable, Sendable {
    case keepers
    case triage

    public var displayName: String {
        switch self {
        case .keepers:
            "Keepers"
        case .triage:
            "Music Triage"
        }
    }

    public var storageKey: String {
        switch self {
        case .keepers:
            "playlist-id.keepers"
        case .triage:
            "playlist-id.triage"
        }
    }
}

public enum TrackActionKind: String, Sendable {
    case add
    case keep
    case delete

    public var displayLabel: String {
        switch self {
        case .add:
            "ADD"
        case .keep:
            "KEEP"
        case .delete:
            "DELETE"
        }
    }
}

public enum TrackIdentityStrength: String, Sendable {
    case strong
    case fallback
}

public struct TrackIdentity: Equatable, Hashable, Sendable {
    public let rawValue: String
    public let strength: TrackIdentityStrength

    public init(rawValue: String, strength: TrackIdentityStrength) {
        self.rawValue = rawValue
        self.strength = strength
    }
}

public struct ObservedTrack: Equatable, Sendable {
    public let title: String
    public let artist: String
    public let albumTitle: String?
    public let playbackStoreID: String?
    public let persistentID: UInt64?
    public let duration: TimeInterval
    public let elapsedTime: TimeInterval
    public let playbackStateDescription: String
    public let isPlaying: Bool
    public let capturedAt: Date

    public init(
        title: String,
        artist: String,
        albumTitle: String?,
        playbackStoreID: String?,
        persistentID: UInt64?,
        duration: TimeInterval,
        elapsedTime: TimeInterval,
        playbackStateDescription: String,
        isPlaying: Bool,
        capturedAt: Date
    ) {
        self.title = title
        self.artist = artist
        self.albumTitle = albumTitle
        self.playbackStoreID = playbackStoreID?.nilIfBlank
        self.persistentID = persistentID
        self.duration = duration
        self.elapsedTime = elapsedTime
        self.playbackStateDescription = playbackStateDescription
        self.isPlaying = isPlaying
        self.capturedAt = capturedAt
    }

    public var normalizedTitle: String {
        Self.normalize(title)
    }

    public var normalizedArtist: String {
        Self.normalize(artist)
    }

    public var metadataSignature: String {
        [normalizedTitle, normalizedArtist, Self.normalize(albumTitle ?? "")]
            .joined(separator: "|")
    }

    public var progressFraction: Double {
        guard duration > 0 else { return 0 }
        return min(max(elapsedTime / duration, 0), 1)
    }

    public var hasUsableMetadata: Bool {
        !normalizedTitle.isEmpty && !normalizedArtist.isEmpty
    }

    public var derivedIdentity: TrackIdentity? {
        if let playbackStoreID, !playbackStoreID.isEmpty {
            return TrackIdentity(rawValue: "store:\(playbackStoreID)", strength: .strong)
        }

        if let persistentID, persistentID != 0, hasUsableMetadata {
            return TrackIdentity(rawValue: "persistent:\(persistentID)", strength: .strong)
        }

        guard hasUsableMetadata else { return nil }
        return TrackIdentity(rawValue: "fallback:\(normalizedTitle)|\(normalizedArtist)", strength: .fallback)
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}

public struct VerifiedTrack: Equatable, Sendable {
    public let identity: TrackIdentity
    public let observation: ObservedTrack
    public let confirmedAt: Date

    public init(identity: TrackIdentity, observation: ObservedTrack, confirmedAt: Date) {
        self.identity = identity
        self.observation = observation
        self.confirmedAt = confirmedAt
    }
}

public enum VerificationSurface: Equatable, Sendable {
    case unavailable(lastConfirmed: VerifiedTrack?)
    case verifying(observed: ObservedTrack, candidateSince: Date, lastConfirmed: VerifiedTrack?)
    case ambiguous(observed: ObservedTrack, reason: String, lastConfirmed: VerifiedTrack?)
    case ready(VerifiedTrack)
}

public struct MembershipState: Equatable, Sendable {
    public var isKeeper: Bool
    public var isTriaged: Bool

    public init(isKeeper: Bool, isTriaged: Bool) {
        self.isKeeper = isKeeper
        self.isTriaged = isTriaged
    }

    public static let unsorted = MembershipState(isKeeper: false, isTriaged: false)
}

public struct ActionOutcome: Equatable, Sendable {
    public let action: TrackActionKind
    public let primaryPlaylist: LogicalPlaylist?
    public let membershipState: MembershipState
    public let libraryAdded: Bool
    public let cleanupRemoved: Bool
    public let warnings: [String]

    public init(
        action: TrackActionKind,
        primaryPlaylist: LogicalPlaylist?,
        membershipState: MembershipState,
        libraryAdded: Bool,
        cleanupRemoved: Bool,
        warnings: [String]
    ) {
        self.action = action
        self.primaryPlaylist = primaryPlaylist
        self.membershipState = membershipState
        self.libraryAdded = libraryAdded
        self.cleanupRemoved = cleanupRemoved
        self.warnings = warnings
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
