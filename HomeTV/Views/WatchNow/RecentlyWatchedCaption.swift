import SwiftUI

/// The caption over a Recently Watched card's still: the episode's title, and the replay glyph beside
/// the season/episode + runtime. Its own `View` struct (not computed properties on the card) so the
/// card body stays a single expression and this composes/previews on its own.
struct RecentlyWatchedCaption: View {
    let item: RecentlyWatchedItem

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Card.overlayLineSpacing) {
            // Plain text, not the title logo the Continue Watching card overlays: a card here is one
            // *episode*, and a show logo tells you nothing about which.
            Text(item.name)
                .font(Theme.Card.overlayTitleFont)
                .foregroundStyle(.white)
                .lineLimit(1)

            HStack(spacing: Theme.Card.overlayControlSpacing) {
                // Replay, not play — and no `ProgressBar`, which is what separates these cards from
                // the Continue Watching row's: there's no progress left to show.
                Image(systemName: "arrow.trianglehead.counterclockwise")
                    .font(Theme.Card.overlayGlyphFont)
                    .foregroundStyle(.white)

                Text(item.metadataText)
                    .font(Theme.Card.overlayMetadataFont)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
        }
        .padding(Theme.Card.overlayInsets)
    }
}
