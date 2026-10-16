import SwiftUI

@main
struct FileToolsApp: App {
    @StateObject private var store = LocationStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}
