import SwiftUI

/// Lets the row preview scroll the row it came from, so a close lands on the last paged title.
///
/// A plain class: `ContentRow` writes the scroll geometry into it on every tick without invalidating
/// itself, and hands it to the gallery inside `RowPreview`.
@MainActor
final class RowScroller {
    /// Horizontal content offset, and the range the row can scroll through.
    var offset: CGFloat = 0
    var offsetRange: ClosedRange<CGFloat> = 0...0
    /// Set by the row: jumps to an absolute x offset, without animation.
    var scrollTo: (CGFloat) -> Void = { _ in }

    /// Scrolls by `delta`, clamped to the row's ends. Returns the distance actually scrolled.
    @discardableResult
    func scroll(by delta: CGFloat) -> CGFloat {
        let applied = Self.clampedDelta(delta, from: offset, within: offsetRange)
        if applied != 0 { scrollTo(offset + applied) }
        return applied
    }

    nonisolated static func clampedDelta(_ delta: CGFloat, from offset: CGFloat, within range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(offset + delta, range.lowerBound), range.upperBound) - offset
    }
}
