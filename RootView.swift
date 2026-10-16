import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var store: LocationStore
    @State private var showPicker = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Locations") {
                    ForEach(store.locations) { loc in
                        NavigationLink(value: loc) {
                            Label(loc.name, systemImage: loc.bookmark == nil ? "iphone" : "folder")
                        }
                        .deleteDisabled(loc.bookmark == nil)
                    }
                    .onDelete { store.remove(at: $0) }
                }

                Section {
                    Text("Tap + to give the app access to a folder (On My iPhone, iCloud Drive, etc.). The app can only touch folders you choose.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Files")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showPicker = true } label: { Image(systemName: "plus") }
                }
            }
            .navigationDestination(for: SavedLocation.self) { loc in
                if let url = store.resolve(loc) {
                    DirectoryView(url: url, title: loc.name)
                } else {
                    ContentUnavailableView("Can't open this folder",
                                           systemImage: "exclamationmark.triangle",
                                           description: Text("Remove it and add it again."))
                }
            }
            .navigationDestination(for: URL.self) { url in
                ItemRouter(url: url)
            }
            .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let url):
                    do { try store.add(folder: url) } catch { errorText = error.localizedDescription }
                case .failure(let error):
                    errorText = error.localizedDescription
                }
            }
            .alert("Error", isPresented: Binding(get: { errorText != nil },
                                                 set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
        }
    }
}

/// Decides whether a tapped URL is a folder or a file.
struct ItemRouter: View {
    let url: URL

    var body: some View {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            DirectoryView(url: url)
        } else {
            FileView(url: url)
        }
    }
}
