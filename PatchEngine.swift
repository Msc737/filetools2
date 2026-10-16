import Foundation

// MARK: - Models

/// One recorded patch / batch-edit operation, so it can be undone later.
struct PatchSession: Codable, Identifiable {
    enum Kind: String, Codable { case replaced, added, edited }
    struct Entry: Codable, Hashable {
        let relativePath: String
        let kind: Kind
    }

    var id = UUID()
    var date = Date()
    var targetPath: String
    var targetName: String
    var label: String
    var entries: [Entry] = []
}

struct PlannedChange: Identifiable, Hashable {
    enum Kind { case add, replace, identical }
    let relativePath: String
    let kind: Kind
    let sourceURL: URL
    var id: String { relativePath }
}

struct ReplaceHit: Identifiable, Hashable {
    let relativePath: String
    let count: Int
    var id: String { relativePath }
}

enum PatchError: LocalizedError {
    case sameFolder
    var errorDescription: String? {
        switch self {
        case .sameFolder: return "The patch folder and the target folder are the same."
        }
    }
}

// MARK: - Session storage (inside the app's own sandbox)

enum PatchStore {
    private static let fm = FileManager.default

    static var root: URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PatchSessions", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func folder(_ s: PatchSession) -> URL {
        root.appendingPathComponent(s.id.uuidString, isDirectory: true)
    }

    static func backupURL(_ s: PatchSession, _ relativePath: String) -> URL {
        folder(s).appendingPathComponent("files", isDirectory: true).appendingPathComponent(relativePath)
    }

    static func save(_ s: PatchSession) throws {
        try fm.createDirectory(at: folder(s), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(s).write(to: folder(s).appendingPathComponent("manifest.json"), options: .atomic)
    }

    static func list(forTarget path: String) -> [PatchSession] {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
                  let s = try? dec.decode(PatchSession.self, from: data),
                  s.targetPath == path else { return nil }
            return s
        }
        .sorted { $0.date > $1.date }
    }

    static func discard(_ s: PatchSession) {
        try? fm.removeItem(at: folder(s))
    }
}

// MARK: - Engine

enum PatchEngine {
    private static let fm = FileManager.default
    private static let maxTextBytes = 2_000_000

    /// Relative paths of regular, non-hidden files under `base`.
    static func listFiles(in base: URL, recursive: Bool) throws -> [String] {
        let subs: [String]
        if recursive {
            subs = try fm.subpathsOfDirectory(atPath: base.path)
        } else {
            subs = try fm.contentsOfDirectory(atPath: base.path)
        }
        return subs.filter { rel in
            if rel.split(separator: "/").contains(where: { $0.hasPrefix(".") }) { return false }
            let full = base.appendingPathComponent(rel).path
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir), !isDir.boolValue else { return false }
            let type = (try? fm.attributesOfItem(atPath: full))?[.type] as? FileAttributeType
            return type != .typeSymbolicLink
        }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    // MARK: Patch a folder with another folder

    /// Compares the patch folder to the target without changing anything.
    static func plan(source: URL, target: URL, recursive: Bool, onlyExisting: Bool) throws -> [PlannedChange] {
        if source.standardizedFileURL.path == target.standardizedFileURL.path { throw PatchError.sameFolder }

        var result: [PlannedChange] = []
        for rel in try listFiles(in: source, recursive: recursive) {
            let src = source.appendingPathComponent(rel)
            let dst = target.appendingPathComponent(rel)

            var isDir: ObjCBool = false
            if fm.fileExists(atPath: dst.path, isDirectory: &isDir) {
                if isDir.boolValue { continue }   // a folder is in the way; skip it
                let same = fm.contentsEqual(atPath: src.path, andPath: dst.path)
                result.append(PlannedChange(relativePath: rel, kind: same ? .identical : .replace, sourceURL: src))
            } else if !onlyExisting {
                result.append(PlannedChange(relativePath: rel, kind: .add, sourceURL: src))
            }
        }
        return result
    }

    /// Copies the patch files into the target, backing up anything it overwrites.
    /// If something fails part-way, everything already done is rolled back.
    static func apply(_ changes: [PlannedChange], target: URL, sourceName: String) throws -> PatchSession {
        var session = PatchSession(targetPath: target.path,
                                   targetName: target.lastPathComponent,
                                   label: "Patch from \(sourceName)")
        do {
            for change in changes where change.kind != .identical {
                let dst = target.appendingPathComponent(change.relativePath)
                switch change.kind {
                case .replace:
                    let backup = PatchStore.backupURL(session, change.relativePath)
                    try fm.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.copyItem(at: dst, to: backup)
                    session.entries.append(.init(relativePath: change.relativePath, kind: .replaced))
                    try fm.removeItem(at: dst)
                    try fm.copyItem(at: change.sourceURL, to: dst)
                case .add:
                    try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                    session.entries.append(.init(relativePath: change.relativePath, kind: .added))
                    try fm.copyItem(at: change.sourceURL, to: dst)
                case .identical:
                    break
                }
            }
            try PatchStore.save(session)
            return session
        } catch {
            try? undo(session, target: target)
            PatchStore.discard(session)
            throw error
        }
    }

    // MARK: Batch find & replace

    static func occurrences(of find: String, in text: String, matchCase: Bool) -> Int {
        guard !find.isEmpty else { return 0 }
        let options: String.CompareOptions = matchCase ? [] : [.caseInsensitive]
        var count = 0
        var range = text.startIndex..<text.endIndex
        while let r = text.range(of: find, options: options, range: range) {
            count += 1
            range = r.upperBound..<text.endIndex
        }
        return count
    }

    /// Finds text files containing `find`. Nothing is modified.
    static func findHits(in target: URL, find: String, extensions: Set<String>,
                         recursive: Bool, matchCase: Bool) throws -> [ReplaceHit] {
        var hits: [ReplaceHit] = []
        for rel in try listFiles(in: target, recursive: recursive) {
            let ext = (rel as NSString).pathExtension.lowercased()
            if !extensions.isEmpty && !extensions.contains(ext) { continue }

            let url = target.appendingPathComponent(rel)
            let size = ((try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
            guard size <= maxTextBytes,
                  let data = try? Data(contentsOf: url),
                  !data.contains(0),
                  let text = String(data: data, encoding: .utf8) else { continue }

            let n = occurrences(of: find, in: text, matchCase: matchCase)
            if n > 0 { hits.append(ReplaceHit(relativePath: rel, count: n)) }
        }
        return hits
    }

    static func applyReplace(_ hits: [ReplaceHit], target: URL, find: String,
                             replacement: String, matchCase: Bool) throws -> PatchSession {
        let shortFind = String(find.prefix(30))
        var session = PatchSession(targetPath: target.path,
                                   targetName: target.lastPathComponent,
                                   label: "Replace \"\(shortFind)\"")
        do {
            for hit in hits {
                let url = target.appendingPathComponent(hit.relativePath)
                let data = try Data(contentsOf: url)
                guard let text = String(data: data, encoding: .utf8) else { continue }

                let backup = PatchStore.backupURL(session, hit.relativePath)
                try fm.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: backup)
                session.entries.append(.init(relativePath: hit.relativePath, kind: .edited))

                let updated = text.replacingOccurrences(of: find, with: replacement,
                                                        options: matchCase ? [] : [.caseInsensitive])
                try updated.write(to: url, atomically: true, encoding: .utf8)
            }
            try PatchStore.save(session)
            return session
        } catch {
            try? undo(session, target: target)
            PatchStore.discard(session)
            throw error
        }
    }

    // MARK: Undo

    /// Puts replaced/edited files back and removes files the patch added.
    static func undo(_ session: PatchSession, target: URL) throws {
        for entry in session.entries.reversed() {
            let dst = target.appendingPathComponent(entry.relativePath)
            switch entry.kind {
            case .replaced, .edited:
                let backup = PatchStore.backupURL(session, entry.relativePath)
                guard fm.fileExists(atPath: backup.path) else { continue }
                if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
                try fm.copyItem(at: backup, to: dst)
            case .added:
                if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
            }
        }
    }
}
