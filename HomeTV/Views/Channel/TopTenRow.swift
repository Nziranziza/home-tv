import SwiftUI

/// The channel screen's Top 10 row: its most popular titles, ranked.
struct TopTenRow: View {
    let metas: [MetaPreview]
    var onSelect: (MetaPreview) -> Void = { _ in }

    var body: some View {
        if !metas.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Row.headerSpacing) {
                RowHeader(title: ChannelShelf.topTen.title, color: Theme.WatchNow.rowHeaderColor)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: Theme.Row.posterCardSpacing) {
                        ForEach(metas.enumerated(), id: \.element.id) { index, meta in
                            TopTenCard(meta: meta, rank: index + 1) { onSelect(meta) }
                        }
                    }
                    .padding(.horizontal, Theme.Row.contentInset)
                    .padding(.vertical, Theme.Row.posterVerticalPadding)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .frame(height: Theme.Row.posterHeight)
            }
            .focusSection()
        }
    }
}
