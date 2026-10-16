import SwiftUI

struct FindReplaceView: View {
    let target: URL
    var onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var find = ""
    @State private var replacement = ""
    @State private var extText = ""
    @State private var recursive = true
    @State private var matchCase = true

    @State private var hits: [ReplaceHit] = []
    @State private var previewed = false
    @State private var showConfirm = false
    @State private var errorText: String?
    @State private var resultText: String?

    private var totalMatches: Int { hits.reduce(0) { $0 + $1.count } }

    private var extensions: Set<String> {
        let parts = extText
            .split(whereSeparator: { $0 == "," || $0 == " " })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased() }
            .filter { !$0.isEmpty }
        return Set(parts)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Find") {
                    TextField("Text to find", text: $find)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Replace with") {
                    TextField("Replacement (can be empty)", text: $replacement)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    TextField("File types, e.g. txt, csv, json", text: $extText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("Include subfolders", isOn: $recursive)
                    Toggle("Match case", isOn: $matchCase)
                } header: {
                    Text("Scope")
                } footer: {
                    Text("Leave file types blank to search every text file in \"\(target.lastPathComponent)\".")
                }

                Section {
                    Button("Preview matches") { preview() }
                        .disabled(find.isEmpty)
                }

                if previewed {
                    Section("Results") {
                        if hits.isEmpty {
                            Text("No matches found.").foregroundStyle(.secondary)
                        } else {
                            Text("\(totalMatches) match(es) in \(hits.count) file(s)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            ForEach(hits) { hit in
                                HStack {
                                    Text(hit.relativePath).lineLimit(2)
                                    Spacer()
                                    Text("\(hit.count)").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Find & Replace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Replace All") { showConfirm = true }
                        .disabled(!previewed || hits.isEmpty)
                }
            }
            // Any change to the inputs invalidates the preview.
            .onChange(of: find) { invalidate() }
            .onChange(of: extText) { invalidate() }
            .onChange(of: recursive) { invalidate() }
            .onChange(of: matchCase) { invalidate() }
            .confirmationDialog("Replace \(totalMatches) match(es) in \(hits.count) file(s)?",
                                isPresented: $showConfirm,
                                titleVisibility: .visible) {
                Button("Replace All") { apply() }
            } message: {
                Text("Originals are backed up first. You can undo from Patch History.")
            }
            .alert("Error", isPresented: Binding(get: { errorText != nil },
                                                 set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
            .alert("Done", isPresented: Binding(get: { resultText != nil },
                                                set: { if !$0 { resultText = nil } })) {
                Button("OK") { dismiss() }
            } message: {
                Text(resultText ?? "")
            }
        }
    }

    private func invalidate() {
        previewed = false
        hits = []
    }

    private func preview() {
        do {
            hits = try PatchEngine.findHits(in: target, find: find, extensions: extensions,
                                            recursive: recursive, matchCase: matchCase)
            previewed = true
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func apply() {
        do {
            let session = try PatchEngine.applyReplace(hits, target: target, find: find,
                                                       replacement: replacement, matchCase: matchCase)
            onFinished()
            resultText = "Edited \(session.entries.count) file(s). You can undo this from Patch History."
        } catch {
            errorText = error.localizedDescription
        }
    }
}
