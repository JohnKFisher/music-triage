import Foundation
import MusicKit

enum MusicTriageServiceError: LocalizedError {
    case permissionDenied
    case unresolvedTrack
    case primaryWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Apple Music permission is required."
        case .unresolvedTrack:
            "The current song could not be resolved safely enough to write."
        case .primaryWriteFailed(let message):
            message
        }
    }
}

actor MusicTriageService {
    private let playlistResolver: PlaylistResolver

    init() {
        self.playlistResolver = PlaylistResolver()
    }

    func requestAuthorization() async -> MusicAuthorization.Status {
        await MusicAuthorization.request()
    }

    func resolveContext(
        for verifiedTrack: VerifiedTrack,
        authorizationStatus: MusicAuthorization.Status
    ) async -> ResolvedTrackContext {
        guard authorizationStatus == .authorized else {
            return ResolvedTrackContext(
                verifiedTrack: verifiedTrack,
                song: nil,
                membership: .unsorted,
                isInLibrary: false,
                resolutionNote: "Authorize Apple Music when you are ready to tag songs."
            )
        }

        do {
            guard let song = try await resolveSong(for: verifiedTrack) else {
                return ResolvedTrackContext(
                    verifiedTrack: verifiedTrack,
                    song: nil,
                    membership: .unsorted,
                    isInLibrary: false,
                    resolutionNote: "This song is visible, but Music Triage cannot identify it safely enough to write yet."
                )
            }

            let isInLibrary = try await librarySong(for: song.id) != nil
            let membership = try await membershipState(for: song)

            return ResolvedTrackContext(
                verifiedTrack: verifiedTrack,
                song: song,
                membership: membership,
                isInLibrary: isInLibrary,
                resolutionNote: nil
            )
        } catch {
            return ResolvedTrackContext(
                verifiedTrack: verifiedTrack,
                song: nil,
                membership: .unsorted,
                isInLibrary: false,
                resolutionNote: "Music Triage hit a lookup problem and kept actions disabled for safety."
            )
        }
    }

    func perform(_ action: TrackActionKind, on context: ResolvedTrackContext) async throws -> ActionOutcome {
        guard let song = context.song else {
            throw MusicTriageServiceError.unresolvedTrack
        }

        switch action {
        case .keep:
            let keepers = try await playlistResolver.resolveWritablePlaylist(for: .keepers)
            do {
                _ = try await MusicLibrary.shared.add(song, to: keepers)
            } catch let error as MusicLibrary.Error where error == .itemAlreadyAdded {
                // Treat repeated add as success.
            } catch {
                throw MusicTriageServiceError.primaryWriteFailed("Could not add the song to Keepers.")
            }

            var warnings: [String] = []
            let libraryAdded = try await addToLibraryIfNeeded(song: song, isInLibrary: context.isInLibrary)
            let cleanupRemoved = await bestEffortRemoval(of: song, from: .triage, warnings: &warnings)

            return ActionOutcome(
                action: .keep,
                primaryPlaylist: .keepers,
                membershipState: MembershipState(isKeeper: true, isTriaged: false),
                libraryAdded: libraryAdded,
                cleanupRemoved: cleanupRemoved,
                warnings: warnings
            )

        case .delete:
            let triage = try await playlistResolver.resolveWritablePlaylist(for: .triage)
            do {
                _ = try await MusicLibrary.shared.add(song, to: triage)
            } catch let error as MusicLibrary.Error where error == .itemAlreadyAdded {
                // Treat repeated add as success.
            } catch {
                throw MusicTriageServiceError.primaryWriteFailed("Could not add the song to Music Triage.")
            }

            var warnings: [String] = []
            let cleanupRemoved = await bestEffortRemoval(of: song, from: .keepers, warnings: &warnings)

            return ActionOutcome(
                action: .delete,
                primaryPlaylist: .triage,
                membershipState: MembershipState(isKeeper: false, isTriaged: true),
                libraryAdded: false,
                cleanupRemoved: cleanupRemoved,
                warnings: warnings
            )
        }
    }

    private func resolveSong(for verifiedTrack: VerifiedTrack) async throws -> Song? {
        if let playbackStoreID = verifiedTrack.observation.playbackStoreID {
            if let song = try await catalogSong(with: playbackStoreID) {
                return song
            }
        }

        if let librarySong = try await uniqueLibrarySong(for: verifiedTrack.observation) {
            return librarySong
        }

        return try await uniqueCatalogSong(for: verifiedTrack.observation)
    }

    private func catalogSong(with playbackStoreID: String) async throws -> Song? {
        var request = MusicCatalogResourceRequest<Song>(
            matching: \.id,
            equalTo: MusicItemID(playbackStoreID)
        )
        request.limit = 1
        return try await request.response().items.first
    }

    private func librarySong(for songID: MusicItemID) async throws -> Song? {
        var request = MusicLibraryRequest<Song>()
        request.limit = 1
        request.filter(matching: \.id, equalTo: songID)
        return try await request.response().items.first
    }

    private func uniqueLibrarySong(for observation: ObservedTrack) async throws -> Song? {
        var request = MusicLibrarySearchRequest(term: "\(observation.title) \(observation.artist)", types: [Song.self])
        request.limit = 10
        let response = try await request.response()
        return uniqueExactMatch(from: response.songs, observation: observation)
    }

    private func uniqueCatalogSong(for observation: ObservedTrack) async throws -> Song? {
        var request = MusicCatalogSearchRequest(term: "\(observation.title) \(observation.artist)", types: [Song.self])
        request.limit = 10
        let response = try await request.response()
        return uniqueExactMatch(from: response.songs, observation: observation)
    }

    private func uniqueExactMatch(
        from songs: MusicItemCollection<Song>,
        observation: ObservedTrack
    ) -> Song? {
        let exactMatches = songs.filter { song in
            normalize(song.title) == observation.normalizedTitle &&
            normalize(song.artistName) == observation.normalizedArtist &&
            albumMatches(song.albumTitle, observation.albumTitle)
        }

        guard exactMatches.count == 1 else {
            return nil
        }

        return exactMatches.first
    }

    private func membershipState(for song: Song) async throws -> MembershipState {
        let keepers = try await playlistResolver.locateExistingPlaylist(for: .keepers)
        let triage = try await playlistResolver.locateExistingPlaylist(for: .triage)

        return MembershipState(
            isKeeper: try await playlist(keepers, contains: song),
            isTriaged: try await playlist(triage, contains: song)
        )
    }

    private func playlist(_ playlist: Playlist?, contains song: Song) async throws -> Bool {
        guard let playlist else { return false }
        let hydrated = try await playlist.with([.entries])
        guard let entries = hydrated.entries else { return false }
        return entries.contains { $0.item?.id == song.id }
    }

    private func addToLibraryIfNeeded(song: Song, isInLibrary: Bool) async throws -> Bool {
        guard !isInLibrary else { return false }
        do {
            try await MusicLibrary.shared.add(song)
            return true
        } catch let error as MusicLibrary.Error where error == .itemAlreadyAdded {
            return true
        }
    }

    private func bestEffortRemoval(
        of song: Song,
        from logicalPlaylist: LogicalPlaylist,
        warnings: inout [String]
    ) async -> Bool {
        do {
            guard let playlist = try await playlistResolver.locateExistingPlaylist(for: logicalPlaylist) else {
                return false
            }

            let hydrated = try await playlist.with([.entries])
            guard let entries = hydrated.entries else { return false }

            let filteredEntries = entries.filter { $0.item?.id != song.id }
            guard filteredEntries.count != entries.count else { return false }

            _ = try await MusicLibrary.shared.edit(hydrated, items: filteredEntries)
            return true
        } catch {
            warnings.append("Primary tag worked, but the opposite playlist cleanup did not finish.")
            return false
        }
    }

    private func albumMatches(_ lhs: String?, _ rhs: String?) -> Bool {
        let normalizedLHS = normalize(lhs ?? "")
        let normalizedRHS = normalize(rhs ?? "")
        return normalizedRHS.isEmpty || normalizedLHS.isEmpty || normalizedLHS == normalizedRHS
    }

    private func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
