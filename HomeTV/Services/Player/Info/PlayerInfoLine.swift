import Foundation

/// The Info tab's `Special Interest • 1 hr 16 min` line.
enum PlayerInfoLine {
    static func text(genre: String?, runtimeSeconds: TimeInterval?, locale: Locale = .current) -> String? {
        let parts = [genre, runtimeSeconds.flatMap { runtime($0, locale: locale) }].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    /// `1 hr 16 min`, `2 hr`, `45 min`, to the nearest minute.
    static func runtime(_ seconds: TimeInterval, locale: Locale = .current) -> String? {
        guard seconds.isFinite, seconds >= 30 else { return nil }
        let minutes = Int((seconds / 60).rounded())
        let style = Measurement<UnitDuration>.FormatStyle(width: .abbreviated, locale: locale, usage: .asProvided)
        var parts: [String] = []
        if minutes >= 60 { parts.append(Measurement(value: Double(minutes / 60), unit: UnitDuration.hours).formatted(style)) }
        if minutes % 60 > 0 { parts.append(Measurement(value: Double(minutes % 60), unit: UnitDuration.minutes).formatted(style)) }
        return parts.joined(separator: " ")
    }
}
