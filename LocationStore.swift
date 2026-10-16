import Foundation
import SwiftUI

/// A folder the user has given the app access to.
/// `bookmark == nil` means "this app's own Documents folder".
struct SavedLocation: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var bookmark: Data?
}

/// Remembers folders the user picked (via security-scoped bookmarks)
/// so access survives app restarts.
@MainActor
final class LocationStore: ObservableObject {
    @Published private(set) var locations: [SavedLocation] = []

    private var activeScopes: [UUID: URL] = [:]
    private let defaultsKey = "savedLocations.v1"

    init() {
        load()
        if !locations.contains(where: { $0.bookmark == nil }) {
            locations.insert(SavedLocation(name: "On This App", bookmark: nil), at: 0)
            save()
        }
    }

    // MARK: Public API

    func add(folder url: URL) throws {
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }

        let data = try url.bookmarkData(options: [],
                                        includingResourceValuesForKeys: nil,
                                        relativeTo: nil)
        locations.append(SavedLocation(name: url.lastPathComponent, bookmark: data))
        save()
    }

    func remove(at offsets: IndexSet) {
        for index in offsets {
            let loc = locations[index]
            if let url = activeScopes[loc.id] {
                url.stopAccessingSecurityScopedResource()
                activeScopes[loc.id] = nil
            }
        }
        locations.remove(atOffsets: offsets)
        save()
    }

    /// Returns a usable URL for the location and starts security-scoped
    /// access (kept open while the app runs, so subfolders keep working).
    func resolve(_ loc: SavedLocation) -> URL? {
        guard let data = loc.bookmark else {
            return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        }
        if let url = activeScopes[loc.id] { return url }

        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: [],
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return nil }

        if url.startAccessingSecurityScopedResource() {
            activeScopes[loc.id] = url
        }
        if stale {
            DispatchQueue.main.async { [weak self] in self?.refreshBookmark(for: loc.id, url: url) }
        }
        return url
    }

    // MARK: Private

    private func refreshBookmark(for id: UUID, url: URL) {
        guard let idx = locations.firstIndex(where: { $0.id == id }),
              let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return }
        locations[idx].bookmark = fresh
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([SavedLocation].self, from: data) else { return }
        locations = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(locations) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
