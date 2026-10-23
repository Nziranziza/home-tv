import Foundation

/// Compares the language codes tracks and devices report: `eng`, `en-US`, `fre` and `fr` all mean
/// something comparable once normalized.
enum SubtitleLanguage {
    /// ISO 639-2/B codes, common in MKV, that Foundation doesn't map to their ISO 639-1 form.
    private static let bibliographic: [String: String] = [
        "alb": "sq", "arm": "hy", "baq": "eu", "bur": "my", "chi": "zh", "cze": "cs", "dut": "nl",
        "fre": "fr", "geo": "ka", "ger": "de", "gre": "el", "ice": "is", "mac": "mk", "mao": "mi",
        "may": "ms", "per": "fa", "rum": "ro", "slo": "sk", "tib": "bo", "wel": "cy",
    ]
    /// Codes that name no language.
    private static let unknown: Set<String> = ["und", "mis", "mul", "zxx", "unknown"]

    /// The language alone, as a two-letter code where one exists: `en` for `eng` or `en-GB`. nil when the
    /// code names no language.
    static func base(_ code: String?) -> String? {
        guard let code else { return nil }
        let lowered = code.trimmingCharacters(in: .whitespaces).lowercased()
        guard let first = lowered.split(whereSeparator: { $0 == "-" || $0 == "_" }).first else { return nil }
        let language = String(first)
        guard !unknown.contains(language) else { return nil }
        if let mapped = bibliographic[language] { return mapped }
        return Locale.LanguageCode(language).identifier(.alpha2) ?? language
    }

    /// Whether the two codes name the same language, ignoring region and script.
    static func matches(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs = base(lhs) else { return false }
        return lhs == base(rhs)
    }

    /// The device's language.
    static var device: String { Locale.preferredLanguages.first ?? "en" }
}
