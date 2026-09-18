import SwiftUI

/// A labelled horizontal row of poster cards — the TV Shows and Movies sections. Geometry is
/// `ContentRow`'s, so a search row and a Watch Now catalog row line up card-for-card.
struct SearchPosterSection: View {
    let title: String
    let items: [MetaPreview]
    var onSelect: (MetaPreview) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Row.headerSpacing) {
            RowHeader(title: title, color: Theme.WatchNow.rowHeaderColor)
            ScrollView(.horizontal) {
                LazyHStack(spacing: Theme.Row.posterCardSpacing) {
                    ForEach(items) { meta in
                        ContentCard(meta: meta) { onSelect(meta) }
                    }
                }
                .padding(.horizontal, Theme.Row.contentInset)
                .padding(.vertical, Theme.Row.posterVerticalPadding)
            }
            .scrollIndicators(.hidden)
            .frame(height: Theme.Row.posterHeight)
            .scrollClipDisabled()
        }
        .focusSection()
    }
}
