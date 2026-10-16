import SwiftUI
import UniformTypeIdentifiers

/// Holds security-scoped access to the chosen patch folder and
/// releases it automatically when the screen goes away.
final class SourceAccess: ObservableObject {
    @Published private(set) var url: URL?
    private var scoped = false

    func set(_ newURL: URL?) {
        stop()
        url = newURL
        if let u = newURL { scoped = u.startAccessingSecurityScopedResource() }
    }

    private func stop() {
        if scoped, let u = url { u.stopAccessingSecurityScopedResource() }
        scoped = false
    }

    deinit { stop() }
}

struct PatchView: View {
    let target: URL
    var onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var access = SourceAccess()

    @State private var showPicker = false
    @State private var recursive = true
    @State private var onlyExisting = false
    @State private var changes: [PlannedChange] = []
    @State private var showConfirm = false
    @State private var errorText: String?
    @State private var resultText: String?

    private var actionable: [PlannedChange] { changes.filter { $0.kind != .identical } }
    private var replaceCount: Int { changes.filter { $0.kind == .replace }.count }
    private var addCount: Int { changes.filter { $0.kind == .add }.count }
    private var sameCount: Int { changes.filter { $0.kind == .identical }.count }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Pick a folder of replacement files. Files with matching names and paths are copied over \"\(target.lastPathComponent)\". Anything overwritten is backed up first, and you can undo it from Patch History.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Patch folder") {
                    Button(access.url == nil ? "Choose patch folder…" : "Choose a different folder…") {
                        showPicker = true
                    }
                    if let url = access.url {
                        Label(url.lastPathComponent, systemImage: "shippingbox")
                    }
                }

                Section("Options") {
                    Toggle("Include subfolders", isOn: $recursive)
                    Toggle("Only replace files that already exist", isOn: $onlyExisting)
                }

                if access.url != nil {
                    Section("Preview") {
                        if changes.isEmpty {
                            Text("No matching files found.").foregroundStyle(.secondary)
                        } else {
                            Text("\(replaceCount) to replace · \(addCount) new · \(sameCount) unchanged")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            ForEach(changes) { change in
                                HStack(spacing: 10) {
                                    Image(systemName: icon(change.kind))
                                        .foregroundStyle(color(change.kind))
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(change.relativePath).lineLimit(2)
                                        Text(label(change.kind))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Patch Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { showConfirm = true }
                        .disabled(actionable.isEmpty)
                }
            }
            .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let url):
                    access.set(url)
                    replan()
                case .failure(let error):
                    errorText = error.localizedDescription
                }
            }
            .onChange(of: recursive) { replan() }
            .onChange(of: onlyExisting) { replan() }
            .confirmationDialog("Apply \(actionable.count) change(s)?",
                                isPresented: $showConfirm,
                                titleVisibility: .visible) {
                Button("Apply Patch") { apply() }
            } message: {
                Text("Replaced files are backed up first.")
            }
            .alert("Error", isPresented: Binding(get: { errorText != nil },
                                                 set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
            .alert("Patch applied", isPresented: Binding(get: { resultText != nil },
                                                         set: { if !$0 { resultText = nil } })) {
                Button("OK") { dismiss() }
            } message: {
                Text(resultText ?? "")
            }
        }
    }

    // MARK: Helpers

    private func icon(_ k: PlannedChange.Kind) -> String {
        switch k {
        case .replace:   return "arrow.triangle.2.circlepath"
        case .add:       return "plus.circle"
        case .identical: return "equal.circle"
        }
    }

    private func color(_ k: PlannedChange.Kind) -> Color {
        switch k {
        case .replace:   return .orange
        case .add:       return .green
        case .identical: return .secondary
        }
    }

    private func label(_ k: PlannedChange.Kind) -> String {
        switch k {
        case .replace:   return "Will replace existing file"
        case .add:       return "Will be added"
        case .identical: return "Already identical – skipped"
        }
    }

    private func replan() {
        guard let source = access.url else { changes = []; return }
        do {
            changes = try PatchEngine.plan(source: source, target: target,
                                           recursive: recursive, onlyExisting: onlyExisting)
        } catch {
            changes = []
            errorText = error.localizedDescription
        }
    }

    private func apply() {
        do {
            let session = try PatchEngine.apply(changes, target: target,
                                                sourceName: access.url?.lastPathComponent ?? "folder")
            onFinished()
            resultText = "\(session.entries.count) file(s) changed. You can undo this from Patch History."
        } catch {
            errorText = error.localizedDescription
        }
    }
}
