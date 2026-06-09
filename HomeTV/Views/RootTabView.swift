import SwiftUI

struct RootTabView: View {
    @State private var selection: Int = Self.initialSelection()

    var body: some View {
        TabView(selection: $selection) {
            WatchNowView()
                .tag(0)
                .tabItem { Text("Watch Now") }

            LibraryView()
                .tag(1)
                .tabItem { Text("Library") }

            SearchView()
                .tag(2)
                .tabItem { Text("Search") }

            SettingsView()
                .tag(3)
                .tabItem { Text("Settings") }
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
