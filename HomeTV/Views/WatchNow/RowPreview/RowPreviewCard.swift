import SwiftUI

/// One gallery card: the title's backdrop, with the row's artwork on top while it grows out of the row.
struct RowPreviewCard: View {
    let meta: MetaPreview
    let sourceShape: ContentCard.Shape
    /// Row artwork over the backdrop; fades out as the card grows.
    let showsSourceArt: Bool
    let showsBackdrop: Bool
    /// Only the centre card and its neighbours decode a full-size backdrop.
    let loadsBackdrop: Bool
    let dim: Double
    let topRadius: CGFloat
    let bottomRadius: CGFloat

    var body: some View {
        // Images ride as overlays on a fixed base: a fill image in a flexible frame would grow the
        // frame to its own size and escape the clip.
        Color(white: 0.12)
            .overlay {
                RemoteImage(url: loadsBackdrop ? Self.backdropURL(for: meta) : nil, targetSize: Theme.Hero.backdropTargetSize) {
                    Color.clear
                }
                .opacity(showsBackdrop ? 1 : 0)
            }
            .overlay {
                RemoteImage(url: ContentCard.artworkURL(for: meta, shape: sourceShape), targetSize: sourceShape.size) {
                    Color.clear
                }
                .opacity(showsSourceArt ? 1 : 0)
            }
            .overlay(Color.black.opacity(dim))
        .clipShape(.rect(
            topLeadingRadius: topRadius,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: topRadius,
            style: .continuous
        ))
        .accessibilityHidden(true)
    }

    /// Same fallback as the detail backdrop, so the decode is shared with it.
    static func backdropURL(for meta: MetaPreview) -> URL? {
        (meta.background ?? meta.poster).flatMap(URL.init(string:))
    }
}
