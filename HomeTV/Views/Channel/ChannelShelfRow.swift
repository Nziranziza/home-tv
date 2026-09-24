import SwiftUI

/// One shelf of a channel screen. Hides itself when the channel has nothing for it.
struct ChannelShelfRow: View {
    let channel: StreamingChannel
    let shelf: ChannelShelf
    var onSelect: (MetaPreview) -> Void = { _ in }

    @State private var metas: [MetaPreview] = []
    @State private var isLoaded = false

    var body: some View {
        if !isLoaded || !metas.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Row.headerSpacing) {
                RowHeader(title: shelf.title, color: Theme.WatchNow.rowHeaderColor)
                if isLoaded {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: Theme.Row.posterCardSpacing) {
                            ForEach(metas) { meta in
                                ContentCard(meta: meta) { onSelect(meta) }
                            }
                        }
                        .padding(.horizontal, Theme.Row.contentInset)
                        .padding(.vertical, Theme.Row.posterVerticalPadding)
                    }
                    .scrollIndicators(.hidden)
                    .scrollClipDisabled()
                    .frame(height: Theme.Row.posterHeight)
                } else {
                    PosterRowPlaceholder()
                }
            }
            .focusSection()
            .task(id: shelf.id) {
                metas = await ChannelCatalogService.shared.titles(for: channel, shelf: shelf) ?? []
                isLoaded = true
            }
        }
    }
}
