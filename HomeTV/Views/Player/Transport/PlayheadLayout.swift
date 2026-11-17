import SwiftUI

/// Places its first subview centred on `progress` of the width, kept inside the bounds, and its second at
/// the trailing edge. Near the end the second gives way, as on the system player: once the first would
/// reach it (with `trailingReserve` to spare for a glyph hanging after the first), the second is hidden
/// and the first runs up to the edge. Keeps the elapsed time under the playhead without a GeometryReader.
struct PlayheadLayout: Layout {
    var progress: Double
    var trailingReserve: CGFloat = 0

    /// The least space between the two.
    private static let minimumGap: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let lead = subviews.first else { return }
        let size = lead.sizeThatFits(.unspecified)
        let centre = bounds.minX + bounds.width * min(max(progress, 0), 1)
        var trailingEdge = bounds.maxX
        if subviews.count > 1 {
            let trailing = subviews[1]
            let trailingSize = trailing.sizeThatFits(.unspecified)
            let leadEnd = min(max(centre - size.width / 2, bounds.minX), bounds.maxX - size.width) + size.width
            let isHidden = leadEnd + trailingReserve + Self.minimumGap > bounds.maxX - trailingSize.width
            // A zero width hides it: the remaining time clips to nothing.
            let placed = isHidden ? CGSize(width: 0, height: trailingSize.height) : trailingSize
            trailing.place(
                at: CGPoint(x: bounds.maxX - placed.width, y: bounds.minY),
                proposal: ProposedViewSize(placed)
            )
            if !isHidden { trailingEdge = bounds.maxX - trailingSize.width }
        }
        let x = min(max(centre - size.width / 2, bounds.minX), max(bounds.minX, trailingEdge - size.width))
        lead.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(size))
    }
}
