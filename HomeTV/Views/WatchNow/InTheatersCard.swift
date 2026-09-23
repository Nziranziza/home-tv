import SwiftUI

/// A title in the In Theaters & At Home row: full-bleed 4:5 key art with the availability caption over
/// a bottom scrim (see `InTheatersCaption`).
///
/// A showcase card, not a catalog one — near twice a `ContentCard` poster, and it carries its own
/// caption — so only about three fit across the screen. Otherwise it is deliberately the same
/// construction as `RecentlyWatchedCard`: same scrim, same corner radius, same `.card` button style,
/// so the rows read as siblings and the focus lift is the system's rather than a hand-rolled one.
struct InTheatersCard: View {
    let item: TheatricalItem
    var action: () -> Void = {}

    private var size: CGSize { Theme.Card.showcaseSize }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(url: artworkURL, targetSize: size, contentMode: .fill) {
                    // Only ever seen while the artwork is in flight or after it fails. The caption
                    // carries no title — the key art is supposed to — so name the film here rather than
                    // leaving a block nobody can identify.
                    ZStack {
                        Color(white: 0.12)
                        Text(item.preview.name)
                            .font(Theme.Card.showcaseCaptionFont)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                }
                .frame(width: size.width, height: size.height)
                .clipped()

                // Bottom scrim. Deeper than the landscape cards' — a poster is as likely to be cream or
                // snow along its bottom edge as black, and the caption has to hold from ten feet either
                // way. Short, because the caption is one line.
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.0), location: 0.66),
                        .init(color: .black.opacity(0.45), location: 0.87),
                        .init(color: .black.opacity(0.88), location: 1.0)
                    ],
                    startPoint: .top, endPoint: .bottom
                )

                InTheatersCaption(item: item)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(.rect(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.card)
        .accessibilityLabel(accessibilityLabel)
    }

    private var artworkURL: URL? { item.preview.poster.flatMap(URL.init(string:)) }

    /// Everything the card shows, said out loud: the title the key art carries, the genre line, and the
    /// availability the glyph stands in for.
    private var accessibilityLabel: String {
        let genres = InTheatersCaptionText.genreLine(for: item.preview)
        let availability = InTheatersCaptionText.tagline(for: item.availability)
        return "\(item.preview.name), \(genres), \(availability)"
    }
}
