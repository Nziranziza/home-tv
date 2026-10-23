import Foundation

/// The transport bar's clock: `01:40` under an hour, `1:14:34` from an hour, the way the system player
/// writes it.
enum PlayerTime {
    static func elapsed(_ seconds: TimeInterval) -> String {
        format(seconds)
    }

    static func remaining(_ seconds: TimeInterval) -> String {
        "-" + format(seconds)
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let whole = seconds.isFinite ? max(0, Int(seconds.rounded(.down))) : 0
        let pattern: Duration.TimeFormatStyle.Pattern = whole >= 3600
            ? .hourMinuteSecond
            : .minuteSecond(padMinuteToLength: 2)
        return Duration.seconds(whole).formatted(.time(pattern: pattern))
    }
}
