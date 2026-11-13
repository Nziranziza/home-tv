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

    /// Codes subtitle add-ons use that aren't ISO 639.
    private static let addonAliases: [String: String] = ["pob": "pt-BR", "pb": "pt-BR"]

    /// The code with its language as two letters where one exists, region and script kept: `fr` for
    /// `fre`, `zh-TW` as is. nil when it names no language.
    static func normalized(_ code: String?) -> String? {
        guard let code else { return nil }
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        if let alias = addonAliases[trimmed.lowercased()] { return alias }
        guard let base = base(trimmed) else { return nil }
        let rest = trimmed.split(whereSeparator: { $0 == "-" || $0 == "_" }).dropFirst().map(String.init)
        return ([base] + rest).joined(separator: "-")
    }

    /// The same language in the same script: `zh-Hans` and `zh-Hant` differ, `en-US` and `en-GB` don't.
    static func sameWritten(_ lhs: String?, _ rhs: String?) -> Bool {
        matches(lhs, rhs) && scriptAndRegion(lhs).script == scriptAndRegion(rhs).script
    }

    /// Whether the two codes name the same language, ignoring region and script.
    static func matches(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs = base(lhs) else { return false }
        return lhs == base(rhs)
    }

    /// The code's script and region, filled in where the code implies them: `zh-TW` is `Hant` and `TW`.
    static func scriptAndRegion(_ code: String?) -> (script: String?, region: String?) {
        guard let code, let base = base(code) else { return (nil, nil) }
        let rest = code.split(whereSeparator: { $0 == "-" || $0 == "_" }).dropFirst()
        let normalized = ([base] + rest.map(String.init)).joined(separator: "-")
        let language = Locale.Language(identifier: Locale.Language(identifier: normalized).maximalIdentifier)
        return (language.script?.identifier, language.region?.identifier)
    }

    /// The device's language.
    static var device: String { Locale.preferredLanguages.first ?? "en" }
}
