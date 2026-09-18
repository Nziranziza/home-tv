import SwiftUI

/// The screen's lead section: the strongest matches across every addon, ranked by `SearchRanker` and
/// laid out two rows deep in a horizontally scrolling grid.
struct SearchTopResultsSection: View {
    let items: [MetaPreview]
    var onSelect: (MetaPreview) -> Void

    private var rows: [GridItem] {
        Array(
            repeating: GridItem(.fixed(Theme.Search.topResultSize.height),
                                spacing: Theme.Search.topResultRowSpacing),
            count: Theme.Search.topResultRows
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Row.headerSpacing) {
            RowHeader(title: "Top Results", color: Theme.WatchNow.rowHeaderColor)
            ScrollView(.horizontal) {
                LazyHGrid(rows: rows, spacing: Theme.Search.topResultSpacing) {
                    ForEach(items) { meta in
                        SearchTopResultCard(meta: meta) { onSelect(meta) }
                    }
                }
                .padding(.horizontal, Theme.Row.contentInset)
                .padding(.vertical, Theme.Search.chipRowPadding)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
        // One vertical focus target, so Up/Down reaches the neighbouring sections however far this one
        // is scrolled sideways — the same treatment `ContentRow` gives the catalog rows.
        .focusSection()
    }
}
