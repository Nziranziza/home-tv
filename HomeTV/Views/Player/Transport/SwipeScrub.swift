import Foundation

/// How far a swipe on the click pad moves the scrub: a slow swipe is fine-grained, a fast one covers more
/// of the title per pad width.
enum SwipeScrub {
    /// Seconds per pad width at or below `slowSpeed`.
    static let baseSpan: TimeInterval = 60
    /// Pad widths per second below which the span stays at `baseSpan`.
    static let slowSpeed = 0.5

    /// Seconds to move for a step of `fraction` of the pad, swiped at `speed` pad widths per second.
    static func seconds(forFraction fraction: Double, speed: Double, duration: TimeInterval) -> TimeInterval {
        let boost = pow(max(1, abs(speed) / slowSpeed), 1.5)
        let span = min(baseSpan * boost, max(baseSpan, duration / 2))
        return fraction * span
    }
}
