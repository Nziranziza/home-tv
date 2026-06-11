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
}
