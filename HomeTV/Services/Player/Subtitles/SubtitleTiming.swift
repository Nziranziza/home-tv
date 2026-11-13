import Foundation

/// The Timing row's 0.1s steps, and how it shows the delay.
enum SubtitleTiming {
    /// Further than any real mistiming.
    static let limit: TimeInterval = 60

    /// `delay` moved by `steps` tenths, kept on the tenth so repeated steps don't drift.
    static func shifted(_ delay: TimeInterval, by steps: Int) -> TimeInterval {
        let tenths = (delay * 10).rounded() + Double(steps)
        return min(max(tenths / 10, -limit), limit)
    }

    /// `+1.5s`, `-0.3s`, or `0.0s`.
    static func text(_ delay: TimeInterval) -> String {
        let number = delay.formatted(
            .number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false))
        )
        return "\(number)s"
    }
}
