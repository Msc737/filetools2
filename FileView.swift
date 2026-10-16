import SwiftUI

/// Shows a text editor for text files, or an info page for everything else.
struct FileView: View {
    let url: URL

    @State private var text = ""
    @State private var original = ""
    @State private var editable = false
    @State private var loaded = false
    @State private var fileSize: Int64 = 0
    @State private var errorText: String?
    @State private var showBackups = false
    @State private var savedFlash = false
    @FocusState private var focused: Bool

    private let maxEditableBytes = 2_000_000
    private var hasChanges: Bool { text != original }

    var body: some View {
        Group {
            if !loaded {
                ProgressView()
            } else if editable {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .padding(.horizontal, 8)
            } else {
                infoPage
            }
        }
        .navigationTitle(url.lastPathComponent + (hasChanges ? " •" : ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if editable {
                    Button(savedFlash ? "Saved ✓" : "Save") { save() }
                        .disabled(!hasChanges)
                    Menu {
                        Button { showBackups = true } label: { Label("Backups…", systemImage: "clock.arrow.circlepath") }
                        ShareLink(item: url)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                } else {
                    ShareLink(item: url)
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
        .sheet(isPresented: $showBackups) {
            BackupsView(fileURL: url) { load() }
        }
        .alert("Error", isPresented: Binding(get: { errorText != nil },
                                             set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
        .onAppear { if !loaded { load() } }
    }

    private var infoPage: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text(url.lastPathComponent).font(.headline)
            Text(Format.bytes(fileSize)).foregroundStyle(.secondary)
            Text("This file can't be edited as text (binary or larger than 2 MB). You can still share or copy it.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
        }
    }

    private func load() {
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            fileSize = Int64(size)
            editable = false
            if size <= maxEditableBytes {
                let data = try Data(contentsOf: url)
                if !data.contains(0), let s = String(data: data, encoding: .utf8) {
                    text = s
                    original = s
                    editable = true
                }
            }
        } catch {
            errorText = error.localizedDescription
        }
        loaded = true
    }

    private func save() {
        do {
            try BackupManager.backup(url)          // keep the previous version first
            try text.write(to: url, atomically: true, encoding: .utf8)
            original = text
            savedFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { savedFlash = false }
        } catch {
            errorText = error.localizedDescription
        }
    }
}
