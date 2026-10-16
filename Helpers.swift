import Foundation

struct FileItem: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    let size: Int64?
    let modified: Date?

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

enum Format {
    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}

/// Returns a URL in `dir` that doesn't collide with an existing file,
/// e.g. "notes.txt" -> "notes 2.txt".
func uniqueURL(in dir: URL, name: String) -> URL {
    let fm = FileManager.default
    var candidate = dir.appendingPathComponent(name)
    guard fm.fileExists(atPath: candidate.path) else { return candidate }

    let base = (name as NSString).deletingPathExtension
    let ext = (name as NSString).pathExtension
    var n = 2
    repeat {
        let newName = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
        candidate = dir.appendingPathComponent(newName)
        n += 1
    } while fm.fileExists(atPath: candidate.path)
    return candidate
}
