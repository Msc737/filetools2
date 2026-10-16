import SwiftUI

/// Lists patches / batch edits made to this folder and lets you undo them.
struct PatchHistoryView: View {
    let target: URL
    var onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sessions: [PatchSession] = []
    @State private var selected: PatchSession?
    @State private var showUndo = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(sessions) { session in
                    Button {
                        selected = session
                        showUndo = true
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.label)
                            Text("\(session.date.formatted(date: .abbreviated, time: .shortened)) · \(session.entries.count) file(s)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                    .swipeActions {
                        Button(role: .destructive) { forget(session) } label: {
                            Label("Forget", systemImage: "trash")
                        }
                    }
                }
            }
            .overlay {
                if sessions.isEmpty {
                    ContentUnavailableView("No Patches Yet",
                                           systemImage: "clock.arrow.circlepath",
                                           description: Text("Patches and batch edits to this folder show up here so you can undo them."))
                }
            }
            .navigationTitle("Patch History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .confirmationDialog("Undo this change?",
                                isPresented: $showUndo,
                                titleVisibility: .visible,
                                presenting: selected) { session in
                Button("Undo", role: .destructive) { undo(session) }
            } message: { _ in
                Text("Edited files go back to their old version and files the patch added are removed. Swipe left on an item to forget it without undoing.")
            }
            .alert("Error", isPresented: Binding(get: { errorText != nil },
                                                 set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
            .onAppear { refresh() }
        }
    }

    private func refresh() {
        sessions = PatchStore.list(forTarget: target.path)
    }

    private func undo(_ session: PatchSession) {
        do {
            try PatchEngine.undo(session, target: target)
            PatchStore.discard(session)
            refresh()
            onChanged()
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// Deletes the saved backups without changing any files.
    private func forget(_ session: PatchSession) {
        PatchStore.discard(session)
        refresh()
    }
}
