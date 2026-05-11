import Foundation
import MusicKit

actor PlaylistResolver {
    private let defaults = UserDefaults.standard

    func locateExistingPlaylist(for logicalPlaylist: LogicalPlaylist) async throws -> Playlist? {
        if let storedID = defaults.string(forKey: logicalPlaylist.storageKey),
           let playlist = try await playlist(forStoredID: storedID) {
            return playlist
        }

        let exactMatches = try await exactNameMatches(for: logicalPlaylist.displayName)
        guard let chosen = choosePlaylist(from: exactMatches) else {
            return nil
        }

        defaults.set(chosen.id.rawValue, forKey: logicalPlaylist.storageKey)
        return chosen
    }

    func resolveWritablePlaylist(for logicalPlaylist: LogicalPlaylist) async throws -> Playlist {
        if let existing = try await locateExistingPlaylist(for: logicalPlaylist) {
            return existing
        }

        let created = try await MusicLibrary.shared.createPlaylist(name: logicalPlaylist.displayName)
        defaults.set(created.id.rawValue, forKey: logicalPlaylist.storageKey)
        return created
    }

    private func playlist(forStoredID storedID: String) async throws -> Playlist? {
        var request = MusicLibraryRequest<Playlist>()
        request.limit = 1
        request.filter(matching: \.id, equalTo: MusicItemID(storedID))
        return try await request.response().items.first
    }

    private func exactNameMatches(for name: String) async throws -> [Playlist] {
        var request = MusicLibraryRequest<Playlist>()
        request.limit = 25
        request.filter(matching: \.name, equalTo: name)
        return try await request.response().items.filter { $0.name == name }
    }

    private func choosePlaylist(from candidates: [Playlist]) -> Playlist? {
        candidates.sorted { lhs, rhs in
            let lhsDate = lhs.libraryAddedDate ?? .distantFuture
            let rhsDate = rhs.libraryAddedDate ?? .distantFuture
            if lhsDate != rhsDate {
                return lhsDate < rhsDate
            }
            return lhs.id.rawValue < rhs.id.rawValue
        }.first
    }
}
