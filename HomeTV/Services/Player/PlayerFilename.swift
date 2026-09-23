import Foundation

/// The name HomeTV hands an external player for a title.
///
/// Not a display string: Infuse's scheme carries no show id, season, episode or year, so the filename
/// is its only hook for identifying what is playing — which drives its artwork, titles and scrobbling.
/// Both forms follow the naming styles Infuse documents for real files.
enum PlayerFilename {

    /// `Severance S01E04 The You You Are.mkv` — the scene convention Infuse parses, where anything
    /// after the `SxxExx` token is trailing detail.
    ///
    /// Flat and show-name-first. The documented folder form (`Show Name/S01E02.mkv`) is rendered
    /// verbatim here, and dropping the show name leaves nothing to identify the series by; both break
    /// matching.
    static func episode(
        showName: String,
        season: Int,
        episode: Int,
        episodeTitle: String? = nil,
        url: URL
    ) -> String {
        let code = "S\(twoDigits(season))E\(twoDigits(episode))"
        let show = sanitized(showName)
        var name = show.isEmpty ? code : "\(show) \(code)"
        if let suffix = episodeTitleSuffix(episodeTitle, season: season, episode: episode) {
            name += " \(suffix)"
        }
        return "\(name).\(fileExtension(of: url))"
    }

    /// `In the Grey (2026).mkv` — Infuse's recommended movie style. The year disambiguates remakes.
    static func movie(title: String, year: Int? = nil, url: URL) -> String {
        let name = sanitized(title)
        guard !name.isEmpty else { return "Movie.\(fileExtension(of: url))" }
        let stem = year.map { "\(name) (\(plainNumber($0)))" } ?? name
        return "\(stem).\(fileExtension(of: url))"
    }

    /// The leading year in an add-on's `releaseInfo`, which is `2026` for a movie and `2019–2023` for
    /// a running series.
    static func year(fromReleaseInfo raw: String?) -> Int? {
        guard let raw, let match = raw.firstMatch(of: /(\d{4})/) else { return nil }
        return Int(match.1)
    }

    /// The episode title, unless it is just a restatement of the number the filename already carries
    /// (`Episode 3`, `E3`, `3`) — appending that would add length and no meaning.
    private static func episodeTitleSuffix(_ title: String?, season: Int, episode: Int) -> String? {
        guard let title else { return nil }
        let cleaned = sanitized(title)
        guard !cleaned.isEmpty else { return nil }
        let collapsed = cleaned.lowercased().replacing(" ", with: "")
        let placeholders = ["episode\(episode)", "e\(episode)", "\(episode)", "s\(season)e\(episode)"]
        guard !placeholders.contains(collapsed) else { return nil }
        return cleaned
    }

    private static let videoExtensions: Set<String> = [
        "mkv", "mp4", "m4v", "avi", "mov", "ts", "m2ts", "wmv", "webm", "mpg", "mpeg"
    ]

    private static func fileExtension(of url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        return videoExtensions.contains(ext) ? ext : "mkv"
    }

    /// Numbers are formatted in the POSIX locale so they stay ASCII and ungrouped in every region —
    /// `2026`, never `2,026`, and `04` rather than a locale's own digits.
    private static func twoDigits(_ value: Int) -> String {
        value.formatted(
            .number.precision(.integerLength(2...)).grouping(.never).locale(Locale(identifier: "en_US_POSIX"))
        )
    }

    private static func plainNumber(_ value: Int) -> String {
        value.formatted(.number.grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }

    /// Strips the characters a filesystem or a parser would choke on and collapses the whitespace, so
    /// the name Infuse sees is the one its matcher expects.
    private static func sanitized(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = name.unicodeScalars.map { illegal.contains($0) ? " " : Character($0) }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }
}
