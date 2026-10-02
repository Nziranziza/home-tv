import SwiftUI

extension View {
    /// An invisible focusable strip just *outside* `edge`, which catches a directional move that would
    /// otherwise escape the view.
    ///
    /// `onMoveCommand` observes a directional press but does not consume it, so the focus engine still
    /// resolves the move to the nearest focusable region that way — on tvOS that can be the sidebar.
    /// Giving the move a real target on the way out is the only way to keep it inside: when the strip
    /// gains focus it runs `action`, which pages the content and hands focus back.
    ///
    /// The strip is focusable only while `isActive`, so at a genuine edge (nothing left to page to) the
    /// move falls through to the neighbouring region as it should.
    ///
    /// - Parameters:
    ///   - edge: the edge the move leaves by — `.leading` for a left press, `.trailing` for right, etc.
    ///   - isActive: whether there is anything to catch; `false` lets the move through.
    ///   - gap: the strip's thickness; the content is inset by it, so callers should shed the same
    ///     amount from an enclosing margin to keep layout unchanged.
    ///   - action: runs when the strip takes focus; it must move focus somewhere real.
    func focusBarrier(
        _ edge: Alignment,
        isActive: Bool,
        gap: CGFloat = 1,
        perform action: @escaping () -> Void
    ) -> some View {
        let isHorizontal = edge == .leading || edge == .trailing
        // Inset the content by `gap` and fill that inset with the strip, so the strip is a real,
        // full-thickness region *inside* this view's bounds and genuinely beyond the content's edge.
        // An `offset` strip sitting outside the bounds is not a focus candidate at all — which is the
        // whole failure this modifier exists to avoid.
        return padding(edge.paddingEdge, gap).overlay(alignment: edge) {
            Color.clear
                .frame(width: isHorizontal ? gap : nil, height: isHorizontal ? nil : gap)
                .frame(maxWidth: isHorizontal ? nil : .infinity,
                       maxHeight: isHorizontal ? .infinity : nil)
                // Going unfocusable the instant it takes focus is the mechanism, not a bug: it forces
                // the engine to rehome focus onto the target `action` just set, so the strip bounces the
                // move rather than holding it. Keeping it focusable here strands focus on the strip, and
                // the *next* press then finds nothing beyond it and escapes.
                .focusable(isActive) { isFocused in
                    if isFocused { action() }
                }
        }
    }
}

private extension Alignment {
    /// The single edge this alignment names, for insetting a focus barrier.
    var paddingEdge: Edge.Set {
        switch self {
        case .leading: .leading
        case .trailing: .trailing
        case .top: .top
        default: .bottom
        }
    }
}
