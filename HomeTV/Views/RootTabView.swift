import SwiftUI

struct RootTabView: View {
    @State private var selection: Int = Self.initialSelection()
    @State private var router = DeepLinkRouter.shared

    var body: some View {
        TabView(selection: $selection) {
            Tab("Search", systemImage: "magnifyingglass", value: 2) {
                SearchView()
            }

            Tab("Watch Now", systemImage: "play.circle", value: 0) {
                WatchNowView()
            }

            Tab("Library", systemImage: "books.vertical", value: 1) {
                LibraryView()
            }

            Tab("Settings", systemImage: "gearshape", value: 3) {
                SettingsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        // A deep link asked for a specific tab (Watch Now hosts detail navigation) — bring it forward.
        .onChange(of: router.requestedTab) { _, newValue in
            guard let newValue else { return }
            selection = newValue
            router.requestedTab = nil
        }
    }

    private static func initialSelection() -> Int {
        switch ProcessInfo.processInfo.environment["INITIAL_TAB"] {
        case "library": 1
        case "search": 2
        case "settings": 3
        default: 0
        }
    }
}

#Preview {
    RootTabView()
        .preferredColorScheme(.light)
}
