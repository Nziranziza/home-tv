import SwiftUI

/// A single Browse by Genre tile: a duotone-tinted poster with the genre name at the bottom-left.
struct GenreTile: View {
    let genre: Genre
    /// Nil until it lands, or if nothing could be found — the tile is then just its duotone gradient.
    var artworkURL: URL?
    var action: () -> Void = {}

    private var size: CGSize { Theme.Card.posterSize }

    var body: some View {
        Button(action: action) {
            GenreTileArtwork(duotone: GenrePalette.duotone(for: genre), artworkURL: artworkURL, size: size)
                .frame(width: size.width, height: size.height)
                .overlay(alignment: .bottomLeading) { label }
                .clipShape(.rect(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.card)
        .frame(width: size.width, height: size.height)
        .accessibilityLabel("Browse \(genre.displayName)")
    }

    /// Genre name over a soft scrim, so it stays legible on the light end of the duotone too.
    private var label: some View {
        Text(genre.displayName)
            .font(Theme.Card.genreLabelFont)
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 40)
            .padding(Theme.Card.overlayInsets)
            .background {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.0), location: 0.0),
                        .init(color: .black.opacity(0.45), location: 1.0)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
    }
}

/// The tile's duotone artwork: the `shadow` colour fills the tile and the `highlight` colour is masked
/// in by the poster's own luminance.
///
/// Do not wrap this in `drawingGroup()` — a rasterized label doesn't occlude the `.card` style's
/// platter, which then shows as white bezels above and below the focused tile.
private struct GenreTileArtwork: View {
    let duotone: GenreDuotone
    let artworkURL: URL?
    let size: CGSize

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [duotone.shadow, duotone.shadow.mix(with: .black, by: 0.45)],
                startPoint: .top, endPoint: .bottom
            )

            if let artworkURL {
                duotone.highlight
                    .mask {
                        // Transparent under the mask, so the gradient shows unchanged until the poster
                        // lands — no grey flash on the way in.
                        RemoteImage(url: artworkURL, targetSize: size, contentMode: .fill) {
                            Color.clear
                        }
                        .frame(width: size.width, height: size.height)
                        .clipped()
                        // Lifts a very dark poster into the middle of the ramp so it keeps its hue.
                        .brightness(0.12)
                        .luminanceToAlpha()
                    }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

#Preview {
    HStack(spacing: Theme.Row.posterCardSpacing) {
        GenreTile(genre: Genre(id: "Family"))
        GenreTile(genre: Genre(id: "Action"))
        GenreTile(genre: Genre(id: "Animation"))
        GenreTile(genre: Genre(id: "Comedy"))
        GenreTile(genre: Genre(id: "Drama"))
        GenreTile(genre: Genre(id: "Horror"))
    }
    .padding(60)
}
