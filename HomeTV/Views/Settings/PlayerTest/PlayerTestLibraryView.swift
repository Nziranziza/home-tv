import SwiftUI

/// Settings → Player Test Library (#148, test branch only): quick tests by format, the catalog's
/// sections, and search across every file.
struct PlayerTestLibraryView: View {
    @State private var library = PlayerTestLibrary()
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                    ScreenTitle(title: "Player Test Library", subtitle: subtitle)
                    PlayerTestHomeActions(library: library)
                    switch library.state {
                    case .loading:
                        PlayerTestStatusView(symbol: nil, title: "Loading the catalog…", message: nil, retry: nil)
                    case .failed(let message):
                        PlayerTestStatusView(symbol: "wifi.exclamationmark", title: "Couldn't load the catalog",
                                             message: message) { Task { await library.load() } }
                    case .loaded(let index):
                        ForEach(PlayerTestPreset.Category.allCases) { category in
                            PlayerTestPresetRow(category: category, counts: index.presetCounts)
                        }
                        PlayerTestSectionGrid(sections: index.sections)
                    }
                }
                .padding(.horizontal, Theme.Layout.horizontalMargin)
                .padding(.vertical, 60)
            }
            .pageHorizontalInsets()
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: PlayerTestRoute.self) { route in
            PlayerTestBrowserView(library: library, route: route)
        }
        .playerTestLaunchAlert(library)
        .task {
            library.refreshLocalFiles()
            await library.load()
        }
    }

    private var subtitle: String {
        guard let index = library.index else { return "Sample files for checking HomeTV's player against Infuse." }
        var text = "\(index.entries.count.formatted()) sample files for checking HomeTV's player against Infuse."
        if let verified = index.verified {
            text += " Verified \(verified.formatted(date: .abbreviated, time: .omitted))."
        }
        return text
    }
}
