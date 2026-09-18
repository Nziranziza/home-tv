import SwiftUI

/// The empty-query state: the catalog-backed Browse set, laid out as a poster grid under the same
/// section header the result sections use, so Browse and Results read as one screen.
struct SearchBrowseSection: View {
    let items: [MetaPreview]
    var onSelect: (MetaPreview) -> Void

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(Theme.Search.posterSize.width), spacing: Theme.Search.posterGutter),
            count: Theme.Search.posterColumns
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Row.headerSpacing) {
            RowHeader(title: "Browse", color: Theme.WatchNow.rowHeaderColor)
            LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Search.posterRowGap) {
                ForEach(items) { meta in
                    ContentCard(meta: meta, sizeOverride: Theme.Search.posterSize) { onSelect(meta) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Row.contentInset)
        }
    }
}
