import SwiftUI
import UniformTypeIdentifiers

struct DirectoryView: View {
    let url: URL
    var title: String? = nil

    @AppStorage("showHidden") private var showHidden = false
    @State private var items: [FileItem] = []
    @State private var search = ""
    @State private var errorText: String?

    @State private var prompt: Prompt = .newFolder
    @State private var promptText = ""
    @State private var showPrompt = false

    @State private var pendingDelete: FileItem?
    @State private var showDelete = false
    @State private var showImporter = false
    @State private var sheet: Tool?

    enum Prompt {
        case newFolder, newFile, rename(FileItem)

        var title: String {
            switch self {
            case .newFolder: return "New Folder"
            case .newFile:   return "New Text File"
            case .rename:    return "Rename"
            }
        }
    }

    enum Tool: String, Identifiable {
        case patch, replace, history
        var id: String { rawValue }
    }

    private var filtered: [FileItem] {
        search.isEmpty ? items : items.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            ForEach(filtered) { item in
                row(item)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { confirmDelete(item) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button { startRename(item) } label: {
                            Label("Rename", systemImage: "pencil")
                        }.tint(.orange)
                    }
                    .contextMenu {
                        Button { startRename(item) } label: { Label("Rename", systemImage: "pencil") }
                        Button { duplicate(item) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                        if !item.isDirectory {
                            ShareLink(item: item.url)
                        }
                        Button(role: .destructive) { confirmDelete(item) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .overlay {
            if items.isEmpty && errorText == nil {
                ContentUnavailableView("Empty Folder", systemImage: "folder")
            }
        }
        .navigationTitle(title ?? url.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search)
        .refreshable { reload() }
        .onAppear { reload() }
        .onChange(of: showHidden) { reload() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { startPrompt(.newFolder) } label: { Label("New Folder", systemImage: "folder.badge.plus") }
                    Button { startPrompt(.newFile) } label: { Label("New Text File", systemImage: "doc.badge.plus") }
                    Button { showImporter = true } label: { Label("Import Files…", systemImage: "square.and.arrow.down") }
                    Divider()
                    Button { sheet = .patch } label: { Label("Patch This Folder…", systemImage: "square.and.arrow.down.on.square") }
                    Button { sheet = .replace } label: { Label("Find & Replace…", systemImage: "text.magnifyingglass") }
                    Button { sheet = .history } label: { Label("Patch History / Undo", systemImage: "clock.arrow.circlepath") }
                    Divider()
                    Toggle("Show Hidden Files", isOn: $showHidden)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert(prompt.title, isPresented: $showPrompt) {
            TextField("Name", text: $promptText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("OK") { commitPrompt() }
        }
        .confirmationDialog("Delete this item?",
                            isPresented: $showDelete,
                            titleVisibility: .visible,
                            presenting: pendingDelete) { item in
            Button("Delete \"\(item.name)\"", role: .destructive) { delete(item) }
        } message: { _ in
            Text("This can't be undone.")
        }
        .alert("Error", isPresented: Binding(get: { errorText != nil },
                                             set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.item],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): importFiles(urls)
            case .failure(let error): errorText = error.localizedDescription
            }
        }
        .sheet(item: $sheet) { tool in
            switch tool {
            case .patch:   PatchView(target: url) { reload() }
            case .replace: FindReplaceView(target: url) { reload() }
            case .history: PatchHistoryView(target: url) { reload() }
            }
        }
    }

    // MARK: Row

    private func row(_ item: FileItem) -> some View {
        NavigationLink(value: item.url) {
            HStack(spacing: 12) {
                Image(systemName: icon(for: item))
                    .foregroundStyle(item.isDirectory ? Color.blue : Color.secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).lineLimit(1)
                    Text(subtitle(for: item))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func icon(for item: FileItem) -> String {
        if item.isDirectory { return "folder.fill" }
        switch item.url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "heic", "webp": return "photo"
        case "mp4", "mov", "m4v":                         return "film"
        case "mp3", "m4a", "wav", "aac":                  return "music.note"
        case "pdf":                                       return "doc.richtext"
        case "zip", "gz", "tar", "7z":                    return "doc.zipper"
        case "txt", "md", "csv", "json", "xml", "plist",
             "yaml", "yml", "log", "ini", "cfg", "swift": return "doc.text"
        default:                                          return "doc"
        }
    }

    private func subtitle(for item: FileItem) -> String {
        var parts: [String] = []
        if !item.isDirectory, let size = item.size { parts.append(Format.bytes(size)) }
        if let date = item.modified { parts.append(date.formatted(date: .abbreviated, time: .shortened)) }
        return parts.joined(separator: " · ")
    }

    // MARK: Loading

    private func reload() {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: keys,
                options: showHidden ? [] : [.skipsHiddenFiles])

            items = urls.map { u in
                let v = try? u.resourceValues(forKeys: Set(keys))
                return FileItem(url: u,
                                isDirectory: v?.isDirectory ?? false,
                                size: v?.fileSize.map { Int64($0) },
                                modified: v?.contentModificationDate)
            }
            .sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            errorText = nil
        } catch {
            items = []
            errorText = error.localizedDescription
        }
    }

    /// Runs a throwing file operation, shows any error, then refreshes the list.
    private func run(_ work: () throws -> Void) {
        do { try work() } catch { errorText = error.localizedDescription }
        reload()
    }

    // MARK: Actions

    private func startPrompt(_ p: Prompt) {
        prompt = p
        switch p {
        case .newFolder: promptText = ""
        case .newFile:   promptText = "untitled.txt"
        case .rename(let item): promptText = item.name
        }
        showPrompt = true
    }

    private func startRename(_ item: FileItem) { startPrompt(.rename(item)) }

    private func commitPrompt() {
        let name = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/") else {
            errorText = "That isn't a valid name."
            return
        }
        let fm = FileManager.default

        run {
            switch prompt {
            case .newFolder:
                try fm.createDirectory(at: url.appendingPathComponent(name, isDirectory: true),
                                       withIntermediateDirectories: false)
            case .newFile:
                let dest = url.appendingPathComponent(name)
                guard !fm.fileExists(atPath: dest.path) else { throw CocoaError(.fileWriteFileExists) }
                try Data().write(to: dest)
            case .rename(let item):
                let dest = item.url.deletingLastPathComponent().appendingPathComponent(name)
                try fm.moveItem(at: item.url, to: dest)
            }
        }
    }

    private func confirmDelete(_ item: FileItem) {
        pendingDelete = item
        showDelete = true
    }

    private func delete(_ item: FileItem) {
        run { try FileManager.default.removeItem(at: item.url) }
    }

    private func duplicate(_ item: FileItem) {
        run {
            try FileManager.default.copyItem(at: item.url,
                                             to: uniqueURL(in: url, name: item.name))
        }
    }

    private func importFiles(_ urls: [URL]) {
        run {
            for source in urls {
                let started = source.startAccessingSecurityScopedResource()
                defer { if started { source.stopAccessingSecurityScopedResource() } }
                try FileManager.default.copyItem(at: source,
                                                 to: uniqueURL(in: url, name: source.lastPathComponent))
            }
        }
    }
}
