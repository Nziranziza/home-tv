import SwiftUI

/// Search screen. The keyboard, query header and "Press ⏯ to change keyboards" hint are all the
/// native tvOS `.searchable` UI; below it we show a focusable poster grid — the live search results
/// when there's a query, otherwise a "Browse" set the user can wander through manually.
struct SearchView: View {
    @State private var viewModel = SearchViewModel()
    @State private var selection: MetaPreview?
    @Environment(\.theme) private var theme

    var body: some View {
        NavigationStack {
            ZStack {
                // Same page background as the Watch Now screen.
                content
            }
            .searchable(text: $viewModel.query, prompt: "Movies, series…")
            .task { await viewModel.loadBrowse() }
            .task(id: viewModel.query) { await viewModel.runSearch() }
            .metaDetailDestinations(selection: $selection)
            .padding(.vertical, 40)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.status {
        case .searching:
            ProgressView().controlSize(.large)
        case .empty:
            ContentUnavailableView.search(text: viewModel.query)
        case .browsing, .results:
            if viewModel.hasNoAddons {
                ContentUnavailableView(
                    "No Addons",
                    systemImage: "puzzlepiece.extension",
                    description: Text("Add a catalog addon in Settings to browse and search.")
                )
            } else {
                SearchBrowseGrid(
                    title: viewModel.status == .results ? "Results" : "Browse",
                    items: viewModel.displayedItems,
                    onSelect: { selection = $0 }
                )
            }
        }
    }
}

/// The poster grid beneath the keyboard. Reuses `ContentCard` for the cards and the shared focus
/// treatment; geometry (260×391 posters, 40pt gutters, 80pt margins) matches the reference frame.
private struct SearchBrowseGrid: View {
    let title: String
    let items: [MetaPreview]
    var onSelect: (MetaPreview) -> Void
    @Environment(\.theme) private var theme

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(Theme.Search.posterSize.width), spacing: Theme.Search.posterGutter),
            count: Theme.Search.posterColumns
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.rowHeader)

                LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Search.posterRowGap) {
                    ForEach(items) { meta in
                        ContentCard(meta: meta, sizeOverride: Theme.Search.posterSize) {
                            onSelect(meta)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Layout.horizontalMargin)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }
}

#Preview {
    SearchView()
}
