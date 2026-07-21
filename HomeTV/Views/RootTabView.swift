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
                // `.sidebarAdaptable` keeps every tab mounted, so Watch Now keeps living while you're on
                // another tab. Pass whether it's the selected tab so its hero can stand its trailer player,
                // Ken Burns pan and auto-advance timer DOWN when it's off-screen — otherwise a live video
                // decodes behind every other screen (the app-wide heaviness).
                WatchNowView(isSelectedTab: selection == 0)
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
