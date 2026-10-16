import Foundation
import CryptoKit

/// Keeps timestamped copies of a file (inside the app's own storage)
/// before it gets overwritten, so any edit can be undone.
enum BackupManager {
    struct Entry: Identifiable {
        let url: URL
        let date: Date
        let size: Int64
        var id: URL { url }
    }

    private static let keepCount = 20
    private static let fm = FileManager.default

    private static var root: URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Backups", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static func folder(for file: URL) -> URL {
        let digest = SHA256.hash(data: Data(file.path.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined().prefix(16)
        return root.appendingPathComponent(String(hash), isDirectory: true)
    }

    static func backup(_ file: URL) throws {
        guard fm.fileExists(atPath: file.path) else { return }
        let dir = folder(for: file)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let dest = dir.appendingPathComponent("\(formatter.string(from: Date()))__\(file.lastPathComponent)")
        try fm.copyItem(at: file, to: dest)

        // Prune oldest beyond the limit.
        let all = list(for: file)
        for old in all.dropFirst(keepCount) { try? fm.removeItem(at: old.url) }
    }

    /// Newest first.
    static func list(for file: URL) -> [Entry] {
        let dir = folder(for: file)
        let keys: [URLResourceKey] = [.creationDateKey, .fileSizeKey]
        guard let urls = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys) else { return [] }
        return urls.compactMap { u in
            guard let v = try? u.resourceValues(forKeys: Set(keys)) else { return nil }
            return Entry(url: u, date: v.creationDate ?? .distantPast, size: Int64(v.fileSize ?? 0))
        }
        .sorted { $0.date > $1.date }
    }

    /// Restores a backup over the file (backing up the current version first).
    static func restore(_ entry: Entry, to file: URL) throws {
        try backup(file)
        let data = try Data(contentsOf: entry.url)
        try data.write(to: file, options: .atomic)
    }
}
