import Foundation
import MusicKit

actor PlaylistResolver {
    private struct PendingCreation {
        let token: UUID
        let task: Task<Playlist, Error>
    }

    private let defaults = UserDefaults.standard
    private var pendingCreations: [LogicalPlaylist: PendingCreation] = [:]

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
        if let pending = pendingCreations[logicalPlaylist] {
            return try await awaitPendingCreation(pending, for: logicalPlaylist)
        }

        let token = UUID()
        let task = Task { [self] in
            try await provisionPlaylist(for: logicalPlaylist)
        }
        let pending = PendingCreation(token: token, task: task)
        pendingCreations[logicalPlaylist] = pending

        return try await awaitPendingCreation(pending, for: logicalPlaylist)
    }

    private func provisionPlaylist(for logicalPlaylist: LogicalPlaylist) async throws -> Playlist {
        if let existing = try await locateExistingPlaylist(for: logicalPlaylist) {
            return existing
        }

        let created = try await MusicLibrary.shared.createPlaylist(name: logicalPlaylist.displayName)

        // A playlist may have appeared while the create request was in flight.
        // Prefer the deterministic existing choice and leave any duplicate untouched.
        if let existing = try await locateExistingPlaylist(for: logicalPlaylist) {
            return existing
        }

        return created
    }

    private func awaitPendingCreation(
        _ pending: PendingCreation,
        for logicalPlaylist: LogicalPlaylist
    ) async throws -> Playlist {
        do {
            let playlist = try await pending.task.value
            defaults.set(playlist.id.rawValue, forKey: logicalPlaylist.storageKey)
            if pendingCreations[logicalPlaylist]?.token == pending.token {
                pendingCreations[logicalPlaylist] = nil
            }
            return playlist
        } catch {
            if pendingCreations[logicalPlaylist]?.token == pending.token {
                pendingCreations[logicalPlaylist] = nil
            }
            throw error
        }
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
