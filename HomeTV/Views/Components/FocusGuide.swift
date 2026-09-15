import SwiftUI

extension View {
    /// A SwiftUI focus guide — the equivalent of UIKit's `UIFocusGuide`, which SwiftUI doesn't expose.
    ///
    /// When the focus engine moves into a row from an adjacent focus section it picks a target by
    /// *geometry* (the nearest focusable along the entry edge), and the declarative default-focus APIs
    /// (`prefersDefaultFocus` / `defaultFocus`) don't override that — they only apply when nothing is
    /// focused, not on directional moves. This places an invisible focusable strip along `edge` (the
    /// side focus arrives from) that spans the row, so it's always the closest target; when it gains
    /// focus it redirects to `target`. The result: entry lands on the item you choose (e.g. the selected
    /// tab) instead of the geometrically nearest one — with no visible round-trip, because no wrong item
    /// is ever focused first.
    ///
    /// The guide is focusable only while `focus` is `nil` (nothing in the row is focused), so moving
    /// back out of the row falls through normally. Apply it inside any `opacity` / `disabled` the row
    /// uses, so the guide is inert whenever the row itself is unfocusable.
    ///
    /// - Parameters:
    ///   - focus: the row's focus binding; entry sets it to `target`.
    ///   - target: the value to focus on entry (e.g. the selected item). No-op when `nil`.
    ///   - edge: the edge focus arrives from — `.bottom` for a row entered from below (the default),
    ///     `.top` from above, `.leading` / `.trailing` for a column entered from the side.
    func focusGuide<Value: Hashable>(
        _ focus: FocusState<Value?>.Binding,
        to target: Value?,
        from edge: Alignment = .bottom
    ) -> some View {
        let isHorizontalEntry = edge == .leading || edge == .trailing
        return overlay(alignment: edge) {
            Color.clear
                .frame(width: isHorizontalEntry ? 1 : nil, height: isHorizontalEntry ? nil : 1)
                .frame(maxWidth: isHorizontalEntry ? nil : .infinity,
                       maxHeight: isHorizontalEntry ? .infinity : nil)
                .focusable(focus.wrappedValue == nil) { isFocused in
                    if isFocused, let target { focus.wrappedValue = target }
                }
        }
    }

    /// The exit-side counterpart to `focusGuide`: an invisible focusable strip just *outside* `edge`,
    /// which catches a directional move that would otherwise escape the view.
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
