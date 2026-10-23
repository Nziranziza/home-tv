import SwiftUI

/// Places its first subview centred on `progress` of the width, kept inside the bounds, and its second at
/// the trailing edge. Keeps the elapsed time under the playhead without measuring with a GeometryReader.
struct PlayheadLayout: Layout {
    var progress: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var trailingEdge = bounds.maxX
        if subviews.count > 1 {
            let trailing = subviews[1]
            let size = trailing.sizeThatFits(.unspecified)
            trailingEdge = bounds.maxX - size.width
            trailing.place(at: CGPoint(x: trailingEdge, y: bounds.minY), proposal: ProposedViewSize(size))
        }
        guard let lead = subviews.first else { return }
        let size = lead.sizeThatFits(.unspecified)
        let centre = bounds.minX + bounds.width * min(max(progress, 0), 1)
        let x = min(max(centre - size.width / 2, bounds.minX), max(bounds.minX, trailingEdge - size.width))
        lead.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(size))
    }
}
