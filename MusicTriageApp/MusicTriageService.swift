import Foundation
import MusicKit

enum MusicTriageServiceError: LocalizedError {
    case permissionDenied
    case unresolvedTrack
    case incompletePagination
    case primaryWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Apple Music permission is required."
        case .unresolvedTrack:
            "The current song could not be resolved safely enough to write."
        case .incompletePagination:
            "Apple Music returned incomplete search results."
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
        reference: TrackReference,
        authorizationStatus: MusicAuthorization.Status
    ) async throws -> ResolvedTrackContext {
        try Task.checkCancellation()
        guard authorizationStatus == .authorized else {
            return ResolvedTrackContext(
                reference: reference,
                verifiedTrack: verifiedTrack,
                song: nil,
                membership: .unknown,
                isInLibrary: false,
                libraryMembershipKnown: false,
                songIdentifierAliases: [],
                resolutionNote: "Authorize Apple Music when you are ready to tag songs."
            )
        }

        guard let resolution = try await safelyResolveSong(for: verifiedTrack) else {
            return ResolvedTrackContext(
                reference: reference,
                verifiedTrack: verifiedTrack,
                song: nil,
                membership: .unknown,
                isInLibrary: false,
                libraryMembershipKnown: false,
                songIdentifierAliases: [],
                resolutionNote: "This song is visible, but Music Triage cannot identify it safely enough to write yet."
            )
        }

        try Task.checkCancellation()
        let membership = await safeMembershipState(
            for: resolution.identifierAliases,
            aliasesComplete: resolution.identifierAliasesComplete
        )
        try Task.checkCancellation()

        let statusNote = resolution.isInLibrary == nil
            ? "Library status could not be verified. Actions are paused until Apple Music can confirm whether this song is in your library."
            : nil

        return ResolvedTrackContext(
            reference: reference,
            verifiedTrack: verifiedTrack,
            song: resolution.song,
            membership: membership,
            isInLibrary: resolution.isInLibrary ?? false,
            libraryMembershipKnown: resolution.isInLibrary != nil,
            songIdentifierAliases: resolution.identifierAliases,
            resolutionNote: statusNote
        )
    }

    func perform(_ action: TrackActionKind, on context: ResolvedTrackContext) async throws -> ActionOutcome {
        guard let song = context.song, context.libraryMembershipKnown else {
            throw MusicTriageServiceError.unresolvedTrack
        }

        switch action {
        case .add:
            guard !context.isInLibrary else {
                throw MusicTriageServiceError.unresolvedTrack
            }
            let libraryAdded = try await addToLibrary(song: song)
            return ActionOutcome(
                action: .add,
                primaryPlaylist: nil,
                membershipState: context.membership,
                libraryAdded: libraryAdded,
                cleanupRemoved: false,
                warnings: []
            )

        case .keep:
            guard context.isInLibrary else {
                throw MusicTriageServiceError.unresolvedTrack
            }
            let keepers = try await playlistResolver.resolveWritablePlaylist(for: .keepers)
            do {
                _ = try await MusicLibrary.shared.add(song, to: keepers)
            } catch let error as MusicLibrary.Error where error == .itemAlreadyAdded {
                // Treat repeated add as success.
            } catch {
                throw MusicTriageServiceError.primaryWriteFailed("Could not add the song to Keepers.")
            }

            var warnings: [String] = []
            if context.membership.isTriaged == true {
                warnings.append("The song remains in Music Triage too. Remove it there manually if desired.")
            }
            return ActionOutcome(
                action: .keep,
                primaryPlaylist: .keepers,
                membershipState: MembershipState(isKeeper: true, isTriaged: context.membership.isTriaged),
                libraryAdded: false,
                cleanupRemoved: false,
                warnings: warnings
            )

        case .delete:
            guard context.isInLibrary else {
                throw MusicTriageServiceError.unresolvedTrack
            }
            let triage = try await playlistResolver.resolveWritablePlaylist(for: .triage)
            do {
                _ = try await MusicLibrary.shared.add(song, to: triage)
            } catch let error as MusicLibrary.Error where error == .itemAlreadyAdded {
                // Treat repeated add as success.
            } catch {
                throw MusicTriageServiceError.primaryWriteFailed("Could not add the song to Music Triage.")
            }

            var warnings: [String] = []
            if context.membership.isKeeper == true {
                warnings.append("The song remains in Keepers too. Remove it there manually if desired.")
            }
            return ActionOutcome(
                action: .delete,
                primaryPlaylist: .triage,
                membershipState: MembershipState(isKeeper: context.membership.isKeeper, isTriaged: true),
                libraryAdded: false,
                cleanupRemoved: false,
                warnings: warnings
            )
        }
    }

    private struct SongResolution {
        let song: Song
        let isInLibrary: Bool?
        let identifierAliases: Set<String>
        let identifierAliasesComplete: Bool
    }

    private struct CatalogAliasResolution {
        let identifiers: Set<String>
        let isComplete: Bool
    }

    private enum LibraryRelationshipResult {
        case present(Set<String>)
        case absent
        case unknown
    }

    private func safelyResolveSong(for verifiedTrack: VerifiedTrack) async throws -> SongResolution? {
        let observation = verifiedTrack.observation

        if let playbackStoreID = observation.playbackStoreID {
            do {
                if let song = try await catalogSong(with: playbackStoreID) {
                    try Task.checkCancellation()
                    // A now-playing store ID is useful only when its catalog metadata
                    // still agrees with the song the playback API reported.
                    guard metadataMatches(song, observation: observation) else {
                        return nil
                    }
                    return try await resolution(forCatalogSong: song, observation: observation)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
            }

            do {
                if let song = try await catalogSongFromDataRequest(with: playbackStoreID) {
                    try Task.checkCancellation()
                    guard metadataMatches(song, observation: observation) else {
                        return nil
                    }
                    return try await resolution(forCatalogSong: song, observation: observation)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
            }
        }

        do {
            if let catalogSong = try await uniqueCatalogSong(for: observation) {
                try Task.checkCancellation()
                return try await resolution(forCatalogSong: catalogSong, observation: observation)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
        }

        do {
            guard let librarySong = try await uniqueLibrarySong(for: observation) else { return nil }
            try Task.checkCancellation()
            let aliases = await catalogAliases(forLibrarySongID: librarySong.id.rawValue)
            return SongResolution(
                song: librarySong,
                isInLibrary: true,
                identifierAliases: aliases.identifiers.union([librarySong.id.rawValue]),
                identifierAliasesComplete: aliases.isComplete
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            return nil
        }
    }

    private func resolution(
        forCatalogSong song: Song,
        observation: ObservedTrack
    ) async throws -> SongResolution {
        let relationship = await libraryRelationship(for: song.id.rawValue)
        try Task.checkCancellation()

        switch relationship {
        case .present(let libraryIDs):
            return SongResolution(
                song: song,
                isInLibrary: true,
                identifierAliases: libraryIDs.union([song.id.rawValue]),
                identifierAliasesComplete: true
            )
        case .absent:
            return SongResolution(
                song: song,
                isInLibrary: false,
                identifierAliases: [song.id.rawValue],
                identifierAliasesComplete: true
            )
        case .unknown:
            // This is the safe fallback when the catalog relationship cannot be
            // read: an exact, fully paginated library search can still prove
            // membership without equating catalog and library IDs.
            do {
                if let librarySong = try await uniqueLibrarySong(for: observation) {
                    let aliases = await catalogAliases(forLibrarySongID: librarySong.id.rawValue)
                    if aliases.isComplete && aliases.identifiers.contains(song.id.rawValue) {
                        return SongResolution(
                            song: librarySong,
                            isInLibrary: true,
                            identifierAliases: aliases.identifiers.union([song.id.rawValue, librarySong.id.rawValue]),
                            identifierAliasesComplete: true
                        )
                    }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
            }
            return SongResolution(
                song: song,
                isInLibrary: nil,
                identifierAliases: [song.id.rawValue],
                identifierAliasesComplete: false
            )
        }
    }

    private func catalogSong(with storeID: String) async throws -> Song? {
        var request = MusicCatalogResourceRequest<Song>(
            matching: \.id,
            equalTo: MusicItemID(storeID)
        )
        request.limit = 1
        return try await request.response().items.first
    }

    private func catalogSongFromDataRequest(with storeID: String) async throws -> Song? {
        guard isValidStoreID(storeID) else { return nil }
        let countryCode = try await MusicDataRequest.currentCountryCode

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.music.apple.com"
        components.path = "/v1/catalog/\(countryCode.lowercased())/songs/\(storeID)"
        components.queryItems = [URLQueryItem(name: "relate", value: "library")]

        guard let url = components.url else { return nil }
        let response = try await MusicDataRequest(urlRequest: URLRequest(url: url)).response()
        let payload = try JSONDecoder().decode(CatalogSongsPayload.self, from: response.data)
        return payload.data.first
    }

    private func libraryRelationship(for catalogID: String) async -> LibraryRelationshipResult {
        guard isValidStoreID(catalogID),
              let countryCode = try? await MusicDataRequest.currentCountryCode else {
            return .unknown
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.music.apple.com"
        components.path = "/v1/catalog/\(countryCode.lowercased())/songs/\(catalogID)"
        components.queryItems = [URLQueryItem(name: "relate", value: "library")]
        guard let url = components.url else { return .unknown }

        do {
            let response = try await MusicDataRequest(urlRequest: URLRequest(url: url)).response()
            let payload = try JSONDecoder().decode(CatalogSongPayload.self, from: response.data)
            guard let resource = payload.data.first,
                  resource.type == "songs",
                  resource.id == catalogID,
                  let relationship = resource.relationships?.library,
                  let firstPage = relationship.data else {
                return .unknown
            }
            guard firstPage.allSatisfy({ $0.type == "library-songs" }) else { return .unknown }

            var identifiers = Set(firstPage.map(\.id))
            var next = relationship.next
            var currentURL = url
            while let nextURLString = next {
                guard let nextURL = validatedNextURL(nextURLString, relativeTo: currentURL) else {
                    return .unknown
                }
                let nextResponse = try await MusicDataRequest(urlRequest: URLRequest(url: nextURL)).response()
                let nextPayload = try JSONDecoder().decode(LibrarySongsPayload.self, from: nextResponse.data)
                guard let pageData = nextPayload.data else {
                    return .unknown
                }
                guard pageData.allSatisfy({ $0.type == "library-songs" }) else { return .unknown }
                identifiers.formUnion(pageData.map(\.id))
                next = nextPayload.next
                currentURL = nextURL
            }

            return identifiers.isEmpty ? .absent : .present(identifiers)
        } catch {
            return .unknown
        }
    }

    private func uniqueLibrarySong(for observation: ObservedTrack) async throws -> Song? {
        var request = MusicLibrarySearchRequest(
            term: "\(observation.title) \(observation.artist)",
            types: [Song.self]
        )
        request.limit = 10
        let response = try await request.response()
        let songs = try await allSongs(from: response.songs)
        return uniqueExactMatch(from: songs, observation: observation)
    }

    private func uniqueCatalogSong(for observation: ObservedTrack) async throws -> Song? {
        var request = MusicCatalogSearchRequest(
            term: "\(observation.title) \(observation.artist)",
            types: [Song.self]
        )
        request.limit = 10
        let response = try await request.response()
        let songs = try await allSongs(from: response.songs)
        return uniqueExactMatch(from: songs, observation: observation)
    }

    private func allSongs(from initialPage: MusicItemCollection<Song>) async throws -> [Song] {
        var page = initialPage
        var songs = Array(page)
        while page.hasNextBatch {
            try Task.checkCancellation()
            guard let nextPage = try await page.nextBatch() else {
                throw MusicTriageServiceError.incompletePagination
            }
            page = nextPage
            songs.append(contentsOf: page)
        }
        return songs
    }

    private func uniqueExactMatch(
        from songs: [Song],
        observation: ObservedTrack
    ) -> Song? {
        let exactMatches = songs.filter {
            metadataMatches($0, observation: observation)
        }
        guard exactMatches.count == 1 else { return nil }
        return exactMatches.first
    }

    private func metadataMatches(
        _ song: Song,
        observation: ObservedTrack
    ) -> Bool {
        guard normalize(song.title) == observation.normalizedTitle,
              normalize(song.artistName) == observation.normalizedArtist else {
            return false
        }

        let observedAlbum = normalize(observation.albumTitle ?? "")
        guard !observedAlbum.isEmpty else { return true }

        let catalogAlbum = normalize(song.albumTitle ?? "")
        guard !catalogAlbum.isEmpty else { return false }
        return observedAlbum == catalogAlbum
    }

    private func catalogAliases(forLibrarySongID librarySongID: String) async -> CatalogAliasResolution {
        guard isValidResourceID(librarySongID) else {
            return CatalogAliasResolution(identifiers: [], isComplete: false)
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.music.apple.com"
        components.path = "/v1/me/library/songs/\(librarySongID)/catalog"
        guard let url = components.url else {
            return CatalogAliasResolution(identifiers: [], isComplete: false)
        }

        do {
            let response = try await MusicDataRequest(urlRequest: URLRequest(url: url)).response()
            var payload = try JSONDecoder().decode(CatalogRelationshipPayload.self, from: response.data)
            guard let firstPage = payload.data else {
                return CatalogAliasResolution(identifiers: [], isComplete: false)
            }
            guard firstPage.allSatisfy({ $0.type == "songs" }) else {
                return CatalogAliasResolution(identifiers: [], isComplete: false)
            }

            var identifiers = Set(firstPage.map(\.id))
            var currentURL = url
            while let nextURLString = payload.next {
                guard let nextURL = validatedNextURL(nextURLString, relativeTo: currentURL) else {
                    return CatalogAliasResolution(identifiers: identifiers, isComplete: false)
                }
                let nextResponse = try await MusicDataRequest(urlRequest: URLRequest(url: nextURL)).response()
                payload = try JSONDecoder().decode(CatalogRelationshipPayload.self, from: nextResponse.data)
                guard let pageData = payload.data else {
                    return CatalogAliasResolution(identifiers: identifiers, isComplete: false)
                }
                guard pageData.allSatisfy({ $0.type == "songs" }) else {
                    return CatalogAliasResolution(identifiers: identifiers, isComplete: false)
                }
                identifiers.formUnion(pageData.map(\.id))
                currentURL = nextURL
            }

            return CatalogAliasResolution(identifiers: identifiers, isComplete: true)
        } catch {
            return CatalogAliasResolution(identifiers: [], isComplete: false)
        }
    }

    private func safeMembershipState(
        for identifierAliases: Set<String>,
        aliasesComplete: Bool
    ) async -> MembershipState {
        MembershipState(
            isKeeper: await safePlaylistMembership(
                for: .keepers,
                identifiers: identifierAliases,
                aliasesComplete: aliasesComplete
            ),
            isTriaged: await safePlaylistMembership(
                for: .triage,
                identifiers: identifierAliases,
                aliasesComplete: aliasesComplete
            )
        )
    }

    private func safePlaylistMembership(
        for logicalPlaylist: LogicalPlaylist,
        identifiers: Set<String>,
        aliasesComplete: Bool
    ) async -> Bool? {
        do {
            guard let playlist = try await playlistResolver.locateExistingPlaylist(for: logicalPlaylist) else {
                return false
            }
            let hydrated = try await playlist.with([.entries])
            guard var entries = hydrated.entries else { return nil }
            var hasUnresolvedEntry = false

            while true {
                if entries.contains(where: { entry in
                    guard let itemID = entry.item?.id.rawValue else {
                        hasUnresolvedEntry = true
                        return false
                    }
                    return identifiers.contains(itemID)
                }) {
                    return true
                }

                guard entries.hasNextBatch else {
                    return aliasesComplete && !hasUnresolvedEntry ? false : nil
                }
                try Task.checkCancellation()
                guard let nextBatch = try await entries.nextBatch() else { return nil }
                entries = nextBatch
            }
        } catch is CancellationError {
            return nil
        } catch {
            return nil
        }
    }

    private func addToLibrary(song: Song) async throws -> Bool {
        do {
            try await MusicLibrary.shared.add(song)
            return true
        } catch let error as MusicLibrary.Error where error == .itemAlreadyAdded {
            // A concurrent add still proves the song is now in the library.
            return true
        }
    }

    private func isValidStoreID(_ value: String) -> Bool {
        value.range(of: "^[0-9]+$", options: .regularExpression) != nil
    }

    private func isValidResourceID(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil
    }

    private func validatedNextURL(_ value: String, relativeTo baseURL: URL) -> URL? {
        guard let url = URL(string: value, relativeTo: baseURL)?.absoluteURL,
              url.scheme == "https",
              url.host == "api.music.apple.com" else {
            return nil
        }
        return url
    }

    private func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}

private struct CatalogSongPayload: Decodable {
    let data: [CatalogSongResource]
}

private struct CatalogRelationshipPayload: Decodable {
    let data: [CatalogRelationshipResource]?
    let next: String?
}

private struct CatalogRelationshipResource: Decodable {
    let id: String
    let type: String
}

private struct CatalogSongsPayload: Decodable {
    let data: MusicItemCollection<Song>
}

private struct CatalogSongResource: Decodable {
    let id: String
    let type: String?
    let attributes: CatalogSongAttributes?
    let relationships: CatalogSongRelationships?
}

private struct CatalogSongAttributes: Decodable {
    let name: String
    let artistName: String
    let albumName: String?
}

private struct CatalogSongRelationships: Decodable {
    let library: LibrarySongsRelationship?
}

private struct LibrarySongsRelationship: Decodable {
    let data: [LibrarySongResource]?
    let next: String?
}

private struct LibrarySongResource: Decodable {
    let id: String
    let type: String
}

private struct LibrarySongsPayload: Decodable {
    let data: [LibrarySongResource]?
    let next: String?
}
