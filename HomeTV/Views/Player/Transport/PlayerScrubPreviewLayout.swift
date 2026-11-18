import SwiftUI

/// Sizes the scrub preview to a share of the track's width at the video's aspect, centred over the
/// playhead and kept inside the track's ends. Bottom-aligned, so it grows upward.
struct PlayerScrubPreviewLayout: Layout {
    /// Measured against the system player's preview.
    static let widthFraction = 0.227

    var progress: Double
    var aspectRatio: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        return CGSize(width: width, height: previewSize(trackWidth: width).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let preview = subviews.first else { return }
        let size = previewSize(trackWidth: bounds.width)
        let centre = bounds.minX + bounds.width * min(max(progress, 0), 1)
        let x = min(max(centre - size.width / 2, bounds.minX), max(bounds.minX, bounds.maxX - size.width))
        preview.place(at: CGPoint(x: x, y: bounds.maxY - size.height), proposal: ProposedViewSize(size))
    }

    private func previewSize(trackWidth: CGFloat) -> CGSize {
        let width = trackWidth * Self.widthFraction
        return CGSize(width: width, height: width / max(aspectRatio, 0.1))
    }
}
