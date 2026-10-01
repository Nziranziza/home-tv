import SwiftUI

/// Everything pinned over the centred card: the metadata, the scrim and the peeking thumbnail strip.
/// One overlay for the whole gallery; only the backdrops slide beneath it.
struct RowPreviewInfoOverlay: View {
    let detail: MetaDetailModel
    let onPlay: (StreamRequest) -> Void
    let onInfo: () -> Void

    /// The logo's decode size, shared with the gallery's prefetch so the reveal is a cache hit.
    static let logoSize = DetailHeroInfo.logoSize

    static func logoURL(for meta: MetaPreview) -> URL? {
        meta.logo.flatMap(URL.init(string:))
    }

    var body: some View {
        let hasStrip = RowPreviewStrip.hasContent(detail)
        ZStack(alignment: .bottomLeading) {
            RowPreviewMetadata(detail: detail, onPlay: onPlay, onInfo: onInfo)
            .padding(.horizontal, Theme.RowPreview.infoLeading)
            .padding(.bottom, Theme.RowPreview.infoBottom)
            // Related titles can land after the reveal; fade the strip in rather than pop it.
            ZStack {
                if hasStrip {
                    RowPreviewStrip(detail: detail)
                        .padding(.leading, Theme.RowPreview.infoLeading)
                        .transition(.opacity)
                }
            }
            .animation(Theme.RowPreview.infoFadeIn, value: hasStrip)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        // Part of the overlay, so it fades with the text and keeps it readable on bright art or video.
        .background {
            RowPreviewScrim()
        }
    }
}
