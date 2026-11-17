import SwiftUI

/// The elapsed time, with the skip, scan, loading or pause glyph beside it. The glyph takes no space, so
/// only the time is centred under the playhead and kept inside the track; near either end the glyph hangs
/// past it, and the bar never moves when one comes or goes.
struct PlayerElapsedTime: View {
    let time: TimeInterval
    let indicator: PlayerTimeIndicator?

    var body: some View {
        HStack(spacing: 0) {
            GlyphSlot(indicator: indicator?.isLeading == true ? indicator : nil, edge: .leading)
            PlayerTimeText(text: PlayerTime.elapsed(time))
            GlyphSlot(indicator: indicator?.isLeading == false ? indicator : nil, edge: .trailing)
        }
    }
}

/// A zero-size slot whose glyph stays mounted and only fades, so it rides a skip's glide with the time
/// instead of appearing at the destination.
private struct GlyphSlot: View {
    let indicator: PlayerTimeIndicator?
    let edge: HorizontalEdge

    /// The last glyph shown, kept while it fades out.
    @State private var lastShown: PlayerTimeIndicator = .paused

    /// Renders as the system player's 14pt once the symbol's side bearing is added.
    private static let gap: CGFloat = 9

    var body: some View {
        PlayerTimeIndicatorView(indicator: indicator ?? lastShown)
            .fixedSize()
            .padding(edge == .leading ? .trailing : .leading, Self.gap)
            // Scoped to the opacity: the slot's position follows the time's glide.
            .animation(.easeInOut(duration: 0.1)) { $0.opacity(indicator == nil ? 0 : 1) }
            .frame(width: 0, height: 0, alignment: edge == .leading ? .trailing : .leading)
            .onChange(of: indicator) { _, new in
                if let new { lastShown = new }
            }
    }
}
