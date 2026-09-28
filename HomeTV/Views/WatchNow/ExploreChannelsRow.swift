import SwiftUI

/// The Explore Channels & Apps row: one card per streaming service, each pushing its channel screen.
/// Renders nothing without a TMDB key, since every channel's catalog comes from there.
struct ExploreChannelsRow: View {
    var onSelect: (StreamingChannel) -> Void = { _ in }

    /// Owned here, as in `BrowseByGenreRow`, so the artwork fetches never re-render the page body.
    @State private var model = ExploreChannelsModel()

    var body: some View {
        if !model.channels.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Row.headerSpacing) {
                RowHeader(title: "Explore Channels & Apps", color: Theme.WatchNow.rowHeaderColor)

                ScrollView(.horizontal) {
                    LazyHStack(spacing: Theme.Row.posterCardSpacing) {
                        ForEach(model.channels) { channel in
                            ChannelCard(
                                channel: channel,
                                artworkURL: model.keyArt[channel.id],
                                logoURL: model.wordmarks[channel.id],
                                brand: model.brandColor(for: channel)
                            ) {
                                onSelect(channel)
                            }
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
            .task { await model.load() }
        }
    }
}
