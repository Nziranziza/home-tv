import Foundation

/// The audio and subtitle languages a stream's add-on labeled it with, parsed once into `StreamMeta`.
///
/// Add-ons signal languages three ways, all handled here: flag emoji (Torrentio's `🇬🇧 / 🇮🇹`),
/// release-name tags (`ITA`, `FRENCH`, `LATINO`, `MULTi`, `DUAL`), and plain text in the description
/// (`Audio: English, Spanish`, `🗣 ENG | ITA`). Languages are stored as BCP-47 identifiers in the order
/// they were found; nothing detected stays empty rather than defaulting to English.
struct StreamLanguages: Hashable, Sendable {
    var audio: [String] = []
    var subtitles: [String] = []
    /// Tagged `MULTi` / `Multi Audio`.
    var isMulti = false
    /// Tagged `DUAL` / `Dual Audio`.
    var isDual = false
    /// Tagged `MultiSubs` / `Multi Subs`.
    var hasMultipleSubtitles = false
    /// The country of the flag a language was detected from (`en` → `US` for 🇺🇸), so it is shown back
    /// with the same flag. Kept per row, since audio and subtitles can carry different flags.
    var audioRegions: [String: String] = [:]
    var subtitleRegions: [String: String] = [:]

    static let empty = StreamLanguages()

    /// Parses `text` (the stream's title, name, and description) plus any languages the add-on reported
    /// in the stream's `subtitles` list.
    static func parse(_ text: String, subtitleCodes: [String] = []) -> StreamLanguages {
        var result = StreamLanguages()
        for line in text.split(whereSeparator: \.isNewline) {
            result.scan(String(line))
        }
        for code in subtitleCodes {
            if let id = normalizedCode(code) { result.subtitles.appendUnique(id) }
        }
        return result
    }

    // MARK: - Display

    /// Compact form for the stream row: up to `maxFlags` flags, the rest collapsed to `+N`. Nil when
    /// nothing was detected, so the row simply omits it.
    func summary(maxFlags: Int = 4, locale: Locale = .current) -> String? {
        guard !audio.isEmpty else { return fallback }
        let shown = labels(for: audio.prefix(maxFlags), regions: audioRegions, locale: locale)
        return audio.count > maxFlags ? "\(shown) +\(audio.count - maxFlags)" : shown
    }

    /// Full form for the details panel, with any multi/dual-audio marker first so truncation can't hide it.
    func detail(locale: Locale = .current) -> String {
        guard !audio.isEmpty else { return fallback ?? "—" }
        let flags = labels(for: audio[...], regions: audioRegions, locale: locale)
        if isMulti { return "Multi · \(flags)" }
        if isDual { return "Dual · \(flags)" }
        return flags
    }

    /// Subtitle languages for the details panel, or nil when the add-on reported none.
    func subtitleDetail(locale: Locale = .current) -> String? {
        if subtitles.isEmpty { return hasMultipleSubtitles ? "Multiple languages" : nil }
        return labels(for: subtitles[...], regions: subtitleRegions, locale: locale)
    }

    /// Flags where a language has one (run together; the glyphs carry their own spacing), names otherwise.
    private func labels(for ids: ArraySlice<String>, regions: [String: String], locale: Locale) -> String {
        ids.reduce(into: "") { result, id in
            if let flag = Self.flag(for: id, region: regions[id]) {
                result += result.isEmpty || result.last?.isLetter == false ? flag : " \(flag)"
            } else {
                result += result.isEmpty ? Self.displayName(for: id, locale: locale) : " \(Self.displayName(for: id, locale: locale))"
            }
        }
    }

    private var fallback: String? {
        if isMulti { return "Multiple languages" }
        if isDual { return "Dual audio" }
        return nil
    }

    static func displayName(for id: String, locale: Locale = .current) -> String {
        let name = id.contains("-")
            ? locale.localizedString(forIdentifier: id)
            : locale.localizedString(forLanguageCode: id)
        return name ?? id.uppercased()
    }

    /// The flag for a language: `region` when given, else the language's main country (`it` → 🇮🇹).
    static func flag(for id: String, region: String? = nil) -> String? {
        let country = region ?? flagOverrides[id]
            ?? Locale.Language(identifier: Locale.Language(identifier: id).maximalIdentifier).region?.identifier
        guard let country, country.count == 2, country.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        let scalars = country.uppercased().unicodeScalars.compactMap { Unicode.Scalar(0x1F1E6 + $0.value - 65) }
        return String(String.UnicodeScalarView(scalars))
    }

    // MARK: - Parsing

    /// Splits `Audio: English | Subtitles: Spanish` at each label so every section is read on its own,
    /// keeping a `Multi` / `Dual` prefix with its label.
    private mutating func scan(_ line: String) {
        let label = /(?i)\b((multi|dual)[ .\-]?)?(audio|sub(title)?s?)\s*:/.wordBoundaryKind(.simple)
        var start = line.startIndex
        for match in line.matches(of: label) where match.range.lowerBound > start {
            scanSection(String(line[start..<match.range.lowerBound]))
            start = match.range.lowerBound
        }
        scanSection(String(line[start...]))
    }

    private mutating func scanSection(_ line: String) {
        // `Subtitles: English, Spanish` / `Subs: ENG` sections list subtitle languages only.
        let subtitleLine = line.contains(/(?i)\bsub(title)?s?\s*:/.wordBoundaryKind(.simple))

        for region in Self.flagRegions(in: line) {
            guard let id = Self.language(forRegion: region) else { continue }
            if subtitleLine {
                if subtitleRegions[id] == nil { subtitleRegions[id] = region }
                subtitles.appendUnique(id)
            } else {
                if audioRegions[id] == nil { audioRegions[id] = region }
                audio.appendUnique(id)
            }
        }

        let tokens = Self.tokens(in: Self.tagRegion(of: line))

        var index = 0
        var subtitlesFollow = false
        while index < tokens.count {
            let token = tokens[index]
            let next = index + 1 < tokens.count ? tokens[index + 1] : nil
            let nextIsSub = next.map(Self.subtitleMarkers.contains) ?? false

            if Self.subtitleMarkers.contains(token) {
                subtitlesFollow = true
            } else if token == "MULTI" {
                // `MULTI.SUB.ENG`: the SUB marker that follows is read next and keeps ENG a subtitle.
                if subtitleLine || nextIsSub { hasMultipleSubtitles = true } else { isMulti = true }
            } else if Self.multiSubtitleMarkers.contains(token) {
                hasMultipleSubtitles = true
                subtitlesFollow = true
            } else if token == "DUAL" {
                if !subtitleLine { isDual = true }
            } else if let id = Self.subtitleTags[token] {
                subtitles.appendUnique(id)
            } else if let id = Self.languageTags[token] {
                if subtitleLine || subtitlesFollow {
                    subtitles.appendUnique(id)
                } else if nextIsSub, !(index + 2 < tokens.count && Self.languageTags[tokens[index + 2]] != nil) {
                    // `Eng.Sub` = English subtitles; in `ENG.SUB.ITA` the marker belongs to ITA.
                    subtitles.appendUnique(id)
                    index += 1
                } else {
                    audio.appendUnique(id)
                }
                index += 1
                continue
            }
            if !Self.subtitleMarkers.contains(token), !Self.multiSubtitleMarkers.contains(token) {
                subtitlesFollow = false
            }
            index += 1
        }
    }

    /// The part of a line to read tags from. A labelled line (`Audio: …`, `🗣 …`, `Multi Audio / …`) is read
    /// whole. A release name leads with the title (`The.Italian.Job.2003…`), so only what follows its first
    /// year / resolution / episode / source / codec marker is read. Anything else (prose, unmarked titles)
    /// contributes flags only.
    private static func tagRegion(of line: String) -> Substring {
        // Emoji labels in both forms: Regex compares whole characters, and 🗣️ (with U+FE0F) isn't 🗣.
        let label = /(?i)\b(audio|languages?|sub(title)?s?)\s*:|🗣️|🗣|🔊️|🔊|\b(multi|dual)[ .\-]?audio\b/
            .wordBoundaryKind(.simple)
        if line.contains(label) { return line[...] }
        let marker = /(?i)(?:^|[^0-9])(?:19|20)[0-9]{2}(?![0-9])|\b[0-9]{3,4}p\b|\bS[0-9]{1,2}E[0-9]{1,3}\b|\b4K\b|\b(web-?dl|webrip|blu-?ray|bdrip|brrip|hdtv|remux|x26[45]|h\.?26[45]|hevc)\b/
            .wordBoundaryKind(.simple)
        guard let match = line.firstMatch(of: marker) else { return line[line.endIndex...] }
        return line[match.range.upperBound...]
    }

    /// Uppercased alphanumeric runs: `MULTi.ENG-FLUX` → `MULTI`, `ENG`, `FLUX`.
    private static func tokens(in text: Substring) -> [String] {
        text.split { !($0.isLetter || $0.isNumber) }.map { $0.uppercased() }
    }

    /// Country codes from regional-indicator pairs, e.g. 🇮🇹 → `IT`.
    private static func flagRegions(in text: String) -> [String] {
        let base: UInt32 = 0x1F1E6
        var regions: [String] = []
        var pending: Unicode.Scalar?
        for scalar in text.unicodeScalars {
            guard (base...0x1F1FF).contains(scalar.value) else { pending = nil; continue }
            if let first = pending {
                let letters = [first, scalar].compactMap { Unicode.Scalar($0.value - base + 65) }
                regions.append(String(String.UnicodeScalarView(letters)))
                pending = nil
            } else {
                pending = scalar
            }
        }
        return regions
    }

    /// The main language of a country, via CLDR's likely subtags (`und-IT` → `it`), with overrides
    /// where a regional variant reads better.
    static func language(forRegion region: String) -> String? {
        if let id = regionOverrides[region] { return id }
        guard !["UN", "EU"].contains(region) else { return nil }
        let likely = Locale.Language(identifier: "und-\(region)").maximalIdentifier
        guard let code = Locale.Language(identifier: likely).languageCode?.identifier,
              code != "und" else { return nil }
        return code
    }

    /// `eng` / `en` / `pob` / `pt-BR` / `zh-Hant` → a two-letter identifier where one exists, keeping any
    /// script and region, for de-duplication.
    private static func normalizedCode(_ code: String) -> String? {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        // `und` is ISO 639's undetermined language.
        guard !trimmed.isEmpty, trimmed.lowercased() != "und" else { return nil }
        if let id = languageTags[trimmed.uppercased()] { return id }
        // Components holds only what the code spells out (no inferred script).
        let language = Locale.Language.Components(identifier: trimmed)
        guard let languageCode = language.languageCode else { return trimmed.lowercased() }
        let base = languageCode.identifier(.alpha2) ?? languageCode.identifier
        return ([base] + [language.script?.identifier, language.region?.identifier].compactMap { $0 })
            .joined(separator: "-")
    }

    private static let regionOverrides: [String: String] = [
        "MX": "es-419",
        "BR": "pt-BR",
        "IN": "hi",
        "CA": "en"
    ]

    /// Flags for languages whose likely country isn't the usual one (English shows 🇬🇧, as Torrentio does).
    private static let flagOverrides: [String: String] = [
        "en": "GB",
        "es-419": "MX",
        "pt-BR": "BR",
        "fr-CA": "CA",
        "yue": "HK"
    ]

    private static let subtitleMarkers: Set<String> = ["SUB", "SUBS", "SUBBED", "SUBTITLE", "SUBTITLES", "SUBTITLED"]

    private static let multiSubtitleMarkers: Set<String> = ["MULTISUB", "MULTISUBS"]

    /// Tokens that name a subtitle language on their own.
    private static let subtitleTags: [String: String] = [
        "ESUB": "en", "ESUBS": "en", "ENGSUB": "en", "ENGSUBS": "en",
        "SUBITA": "it", "SUBSITA": "it",
        "VOSTFR": "fr", "VOST": "fr"
    ]

    /// Release-name tags and plain-text names → BCP-47. Short codes that collide with common words or
    /// group names (IND, ROM, PER, BEN, …) are left out.
    private static let languageTags: [String: String] = [
        "ENG": "en", "ENGLISH": "en",
        "ITA": "it", "ITALIAN": "it", "ITALIANO": "it",
        "FRA": "fr", "FRE": "fr", "FRENCH": "fr", "TRUEFRENCH": "fr", "VF": "fr", "VFF": "fr", "VF2": "fr",
        "VFI": "fr", "VOF": "fr", "VFQ": "fr-CA", "FRANCAIS": "fr", "FRANÇAIS": "fr",
        "GER": "de", "DEU": "de", "GERMAN": "de", "DEUTSCH": "de",
        "SPA": "es", "ESP": "es", "SPANISH": "es", "CASTELLANO": "es", "ESPANOL": "es", "ESPAÑOL": "es",
        "LAT": "es-419", "LATINO": "es-419",
        "POR": "pt", "PORTUGUESE": "pt", "DUBLADO": "pt-BR", "POB": "pt-BR",
        "HIN": "hi", "HINDI": "hi",
        "TAM": "ta", "TAMIL": "ta", "TEL": "te", "TELUGU": "te", "MALAYALAM": "ml", "KANNADA": "kn",
        "BENGALI": "bn",
        "JAP": "ja", "JPN": "ja", "JAPANESE": "ja",
        "KOR": "ko", "KOREAN": "ko",
        "CHI": "zh", "CHINESE": "zh", "MANDARIN": "zh", "CANTONESE": "yue",
        "RUS": "ru", "RUSSIAN": "ru", "UKR": "uk", "UKRAINIAN": "uk",
        "ARA": "ar", "ARABIC": "ar", "TUR": "tr", "TURKISH": "tr",
        "POL": "pl", "POLISH": "pl", "DUTCH": "nl", "NLD": "nl",
        "SWE": "sv", "SWEDISH": "sv", "DANISH": "da", "FIN": "fi", "FINNISH": "fi", "NORWEGIAN": "nb",
        "CZE": "cs", "CZECH": "cs", "HUN": "hu", "HUNGARIAN": "hu", "GRE": "el", "GREEK": "el",
        "HEB": "he", "HEBREW": "he", "THAI": "th", "VIE": "vi", "VIETNAMESE": "vi",
        "INDONESIAN": "id", "ROMANIAN": "ro", "PERSIAN": "fa", "FARSI": "fa"
    ]
}

private extension Array where Element == String {
    mutating func appendUnique(_ element: String) {
        if !contains(element) { append(element) }
    }
}
