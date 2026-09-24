import Foundation

/// TMDB API credentials and endpoint/image helpers. The key identifies *this app* to TMDB — it is
/// not a per-user token, so (like `TraktConfig`) it lives in `Secrets.xcconfig` (gitignored), is
/// injected into Info.plist at build time via `$(TMDB_API_KEY)` substitution (see project.yml), and
/// is read here at runtime with `Bundle.main`. Nothing secret is committed to source.
///
/// We use the **v3 API key** (the short 32-char value), sent as the `api_key` query parameter — not
/// the v4 Read Access Token / bearer header.
///
/// Leaving the value blank is fine — `isConfigured` is false and enrichment simply never runs, so
/// the app behaves exactly as it does today (graceful degradation, same as Trakt).
enum TMDBConfig {
    static let apiKey = infoValue("TMDB_API_KEY")

    static let apiBaseURL = URL(string: "https://api.themoviedb.org/3")!
    static let imageBaseURL = URL(string: "https://image.tmdb.org/t/p")!

    /// Metadata language. Fixed to en-US for determinism (no picker, not device locale).
    static let language = "en-US"

    /// Release-window region for the theatrical/VOD endpoints — what is in theatres and when a title
    /// reaches digital are both per-country. Pinned to US for the same reason as `language`: the app
    /// has no region picker, and a device-locale region would silently change the row's contents.
    static let region = "US"

    /// Calendar the release windows are measured on. A TMDB release date is a plain calendar day with
    /// no time of day, and these are US release dates — so the day boundary has to be a US one. Left to
    /// the format style's default the dates would roll over on GMT, up to five hours early, which is
    /// enough to call a title available the day before it is.
    static let releaseTimeZone = TimeZone(identifier: "America/New_York") ?? .gmt

    /// The same calendar, for counting days back from today.
    static let releaseCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = releaseTimeZone
        return calendar
    }()

    /// `days` calendar days before `date`. Calendar days rather than fixed 24-hour spans: across a
    /// daylight-saving change a fixed span lands an hour out, which is enough to format as the
    /// neighbouring day and move a window edge. Falls back to the fixed span if the calendar cannot
    /// answer, which it always can for a plain day offset.
    static func date(_ days: Int, daysBefore date: Date) -> Date {
        releaseCalendar.date(byAdding: .day, value: -days, to: date)
            ?? date.addingTimeInterval(-Double(days) * 24 * 60 * 60)
    }

    /// A date as TMDB's `YYYY-MM-DD` query format, on that calendar. Shared by the release-window
    /// queries and the day key their results are cached under, so the two always agree on when today
    /// ends.
    static func day(_ date: Date) -> String {
        date.formatted(
            Date.ISO8601FormatStyle(dateSeparator: .dash, timeZone: releaseTimeZone)
                .year().month().day()
        )
    }

    /// True once the key is present. All enrichment keys off this.
    static var isConfigured: Bool { !apiKey.isEmpty }

    /// Build a full image URL for a TMDB relative path (e.g. `/abc.jpg`) at a given size token.
    /// Returns nil when the path is missing, so callers can fall back to addon artwork.
    static func imageURL(path: String?, size: ImageSize) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        let normalized = path.hasPrefix("/") ? path : "/" + path
        return imageBaseURL.appending(path: size.rawValue).appending(path: normalized)
    }

    /// TMDB image size tokens (see https://developer.themoviedb.org/docs/image-basics).
    enum ImageSize: String {
        case w185      // profile thumbnails
        case w300
        case w500      // posters / logos
        case w780      // episode stills
        case w1280     // backdrops (hero)
        case original
    }

    /// Read an Info.plist string injected from the xcconfig, trimming stray whitespace/newlines from
    /// copy-paste. Returns "" when unset (key absent or left blank in the xcconfig).
    private static func infoValue(_ key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return "" }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
