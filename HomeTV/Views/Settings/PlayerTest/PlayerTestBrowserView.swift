import SwiftUI

/// Search and filter within a scope, with the focused file explained beside the results.
struct PlayerTestBrowserView: View {
    let library: PlayerTestLibrary
    private let scope: PlayerTestScope?
    @State private var query = PlayerTestQuery()
    @State private var results: [PlayerTestEntry] = []
    @State private var selection = PlayerTestSelection()
    @Environment(\.theme) private var theme

    init(library: PlayerTestLibrary, route: PlayerTestRoute) {
        self.library = library
        scope = library.scope(for: route)
    }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            if let scope {
                VStack(alignment: .leading) {
                    PlayerTestBrowserHeader(scope: scope, resultCount: results.count)
                    PlayerTestBrowserControls(scope: scope, query: $query)
                    HStack(alignment: .top, spacing: Theme.Spacing.section) {
                        PlayerTestResultList(library: library, results: results, query: query,
                                             isLocal: scope.isLocal, selection: selection)
                        PlayerTestDetailPanel(selection: selection, scope: scope)
                            .frame(width: 660)
                    }
                }
                .padding(.horizontal, Theme.Layout.horizontalMargin)
                .padding(.top, Theme.Spacing.section)
            } else {
                ContentUnavailableView("Catalog Not Loaded", systemImage: "wifi.exclamationmark")
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .playerTestLaunchAlert(library)
        .onChange(of: query, initial: true) {
            results = query.apply(to: scope?.entries ?? [])
        }
    }
}

private struct PlayerTestBrowserHeader: View {
    let scope: PlayerTestScope
    let resultCount: Int
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: scope.symbol)
            VStack(alignment: .leading) {
                Text(scope.title).font(.title2).bold()
                Text(scope.summary).font(.callout).foregroundStyle(theme.secondaryText).lineLimit(1)
            }
            Spacer()
            Text(countText).font(.callout).foregroundStyle(theme.secondaryText)
        }
        .foregroundStyle(theme.primaryText)
    }

    private var countText: String {
        let total = scope.entries.count
        return resultCount == total ? "\(total.formatted()) files" : "\(resultCount.formatted()) of \(total.formatted()) files"
    }
}
