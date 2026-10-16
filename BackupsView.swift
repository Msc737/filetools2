import SwiftUI

struct BackupsView: View {
    let fileURL: URL
    var onRestored: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var entries: [BackupManager.Entry] = []
    @State private var selected: BackupManager.Entry?
    @State private var showConfirm = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List(entries) { entry in
                Button {
                    selected = entry
                    showConfirm = true
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.date.formatted(date: .abbreviated, time: .standard))
                        Text(Format.bytes(entry.size))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
            }
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView("No Backups Yet",
                                           systemImage: "clock.arrow.circlepath",
                                           description: Text("A backup is made automatically each time you save."))
                }
            }
            .navigationTitle("Backups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .confirmationDialog("Restore this version?",
                                isPresented: $showConfirm,
                                titleVisibility: .visible,
                                presenting: selected) { entry in
                Button("Restore") { restore(entry) }
            } message: { _ in
                Text("Your current version is backed up first.")
            }
            .alert("Error", isPresented: Binding(get: { errorText != nil },
                                                 set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
            .onAppear { entries = BackupManager.list(for: fileURL) }
        }
    }

    private func restore(_ entry: BackupManager.Entry) {
        do {
            try BackupManager.restore(entry, to: fileURL)
            onRestored()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
