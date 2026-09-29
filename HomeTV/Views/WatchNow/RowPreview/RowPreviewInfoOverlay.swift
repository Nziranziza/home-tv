import SwiftUI

/// Everything pinned over the centred card: the metadata, the scrim and the peeking thumbnail strip.
/// One overlay for the whole gallery; only the backdrops slide beneath it.
struct RowPreviewInfoOverlay: View {
    let detail: MetaDetailModel
    var focus: FocusState<RowPreviewGallery.Control?>.Binding
    let areControlsEnabled: Bool
    let onPlay: (StreamRequest) -> Void
    let onInfo: () -> Void
    let onOpenEpisode: (Video) -> Void
    let onOpenRelated: (MetaPreview) -> Void
    /// Up from the buttons, back to paging.
    let onExitControls: () -> Void

    @State private var stripHeight: CGFloat = 0

    /// The logo's decode size, shared with the gallery's prefetch so the reveal is a cache hit.
    static let logoSize = CGSize(width: 280, height: 120)

    static func logoURL(for meta: MetaPreview) -> URL? {
        meta.logo.flatMap(URL.init(string:))
    }

    /// Focus in the strip raises the whole overlay until the strip clears the card's bottom edge.
    private var isStripFocused: Bool {
        if case .strip = focus.wrappedValue { true } else { false }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RowPreviewMetadata(
                detail: detail,
                focus: focus,
                areControlsEnabled: areControlsEnabled,
                onPlay: onPlay,
                onInfo: onInfo,
                onExitControls: onExitControls
            )
            .padding(.horizontal, Theme.RowPreview.infoLeading)
            .padding(.bottom, Theme.RowPreview.infoBottom)
            if RowPreviewStrip.hasContent(detail) {
                RowPreviewStrip(
                    detail: detail,
                    focus: focus,
                    onPlay: onPlay,
                    onOpenEpisode: onOpenEpisode,
                    onOpenRelated: onOpenRelated
                )
                // A fresh strip per title, so it opens on that title's up-next episode.
                .id(detail.metaID)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { stripHeight = $0 }
                // Only the top peeks above the card's bottom edge.
                .offset(y: stripHeight - Theme.RowPreview.stripPeek)
                .disabled(!areControlsEnabled)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .offset(y: isStripFocused ? -(stripHeight + Theme.RowPreview.stripRaisedBottom - Theme.RowPreview.stripPeek) : 0)
        .animation(Theme.RowPreview.stripRise, value: isStripFocused)
        // Part of the overlay, so it fades with the text and keeps it readable on bright art or video.
        .background {
            RowPreviewScrim()
        }
    }
}
