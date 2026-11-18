import SwiftUI

/// The matching files. A stack, not a `List`: a `List` row takes focus as one cell, so Right couldn't
/// reach a row's Infuse button.
struct PlayerTestResultList: View {
    let library: PlayerTestLibrary
    let results: [PlayerTestEntry]
    let query: PlayerTestQuery
    let isLocal: Bool
    let selection: PlayerTestSelection

    var body: some View {
        if results.isEmpty {
            PlayerTestEmptyResults(query: query, isLocal: isLocal)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.stack) {
                    ForEach(results) { entry in
                        PlayerTestItemRow(library: library, entry: entry, selection: selection)
                    }
                }
                .padding(Theme.Spacing.stack)
            }
            .focusSection()
        }
    }
}

private struct PlayerTestEmptyResults: View {
    let query: PlayerTestQuery
    let isLocal: Bool

    var body: some View {
        if !query.text.isEmpty {
            ContentUnavailableView.search(text: query.text)
        } else if isLocal {
            ContentUnavailableView(
                "No Files on This Apple TV",
                systemImage: "internaldrive",
                description: Text("Copy clips with: xcrun devicectl device copy to --domain-type appDataContainer --domain-identifier com.hometv.HomeTV --destination Library/Caches/")
            )
        } else {
            ContentUnavailableView("No Matching Files", systemImage: "line.3.horizontal.decrease.circle",
                                   description: Text("Clear a filter to see more."))
        }
    }
}
