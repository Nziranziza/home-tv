import SwiftUI

struct RootTabView: View {
    @State private var selection: Int = Self.initialSelection()

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
