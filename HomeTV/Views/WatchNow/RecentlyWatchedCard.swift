import SwiftUI

/// A finished title in the Recently Watched row: landscape episode still with the title over a bottom
/// scrim, and a replay glyph beside the season/episode + runtime.
///
/// Deliberately close to `ContinueWatchingCard` — same geometry, same corner radius, same scrim — so
/// the two rows read as siblings, with two differences that say "this one is done": a replay glyph
/// instead of a play glyph, and **no progress bar** (there is no progress left to show).
struct RecentlyWatchedCard: View {
    let item: RecentlyWatchedItem
    var action: () -> Void = {}

    private var size: CGSize { Theme.Card.continueWatchingSize }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(url: item.artworkURL, targetSize: size, contentMode: .fill) {
                    Color(white: 0.12)
                }
                .frame(width: size.width, height: size.height)
                .clipped()

                // Bottom scrim — keeps the title + metadata clear over any still.
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.0), location: 0.45),
                        .init(color: .black.opacity(0.6), location: 1.0)
                    ],
                    startPoint: .top, endPoint: .bottom
                )

                bottomContent
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.card)
        .accessibilityLabel(accessibilityLabel)
    }

    private var bottomContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Plain text, not the title logo the Continue Watching card overlays: a card here is one
            // *episode*, and a show logo tells you nothing about which.
            Text(item.name)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)

            metadataRow
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private var metadataRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.trianglehead.counterclockwise")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)

            Text(item.metadataText)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }

    private var accessibilityLabel: String {
        let metadata = item.metadataText
        guard !metadata.isEmpty else { return "Rewatch \(item.name)" }
        return "Rewatch \(item.name), \(metadata)"
    }
}
