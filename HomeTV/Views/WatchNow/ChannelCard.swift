import SwiftUI

/// A channel in the Explore Channels & Apps row: key art over a brand panel carrying the service's
/// wordmark.
struct ChannelCard: View {
    let channel: StreamingChannel
    let artworkURL: URL?
    let logoURL: URL?
    let brand: BrandColor
    var action: () -> Void = {}

    private var size: CGSize { Theme.Card.posterSize }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                // Top-aligned so the poster's own title block stays in frame.
                RemoteImage(url: artworkURL, targetSize: size, contentMode: .fill) {
                    brand.color
                }
                .frame(width: size.width, height: size.height)
                .frame(height: Theme.Channel.cardArtHeight, alignment: .top)
                .clipped()

                ChannelWordmark(channel: channel, logoURL: logoURL, maxSize: Theme.Channel.logoMaxSize)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(brand.color)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(.rect(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.card)
        .accessibilityLabel(channel.name)
    }
}
