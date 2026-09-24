import SwiftUI

/// The caption over a showcase card's key art: a filled glyph beside "Movie · Sci-Fi · Adventure".
/// Its own `View` struct (not computed properties on the card) so the card body stays a single
/// expression, mirroring `RecentlyWatchedCaption`.
///
/// One line, and no title: the cards this mirrors carry their title in the key art itself, and a
/// second line of copy under this one lands squarely on the baked-in wordmark of most posters. The
/// availability is still said — by the glyph here, and in full in the card's accessibility label.
/// Nothing here changes on focus; per-line focus styling is what made the cast row animate apart.
struct InTheatersCaption: View {
    let item: TheatricalItem

    var body: some View {
        HStack(spacing: Theme.Card.showcaseGlyphSpacing) {
            Image(systemName: InTheatersCaptionText.glyph(for: item.availability))
                .font(Theme.Card.showcaseGlyphFont)
                .foregroundStyle(.white)
                .frame(
                    width: Theme.Card.showcaseGlyphDiameter,
                    height: Theme.Card.showcaseGlyphDiameter
                )
                .background(.black, in: .circle)

            Text(InTheatersCaptionText.genreLine(for: item.preview))
                .font(Theme.Card.showcaseCaptionFont)
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(Theme.Card.showcaseInsets)
    }
}
