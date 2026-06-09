import Foundation

/// View-facing enrichment payload produced by `TMDBService` from raw `TMDB*` responses. This is the
/// sidecar that `MetaDetailView` reads alongside the base addon `Meta`, so the large detail view
/// doesn't need to know about TMDB's wire format.
///
/// Every field is optional / empty-by-default: the view prefers TMDB values when present and falls
/// back to the addon `Meta`, never blanking out existing data when TMDB is missing a field.
struct Enrichment: Sendable, Hashable {
    // Artwork
    var logoURL: URL?
    var backdropURL: URL?

    // Basic info
    var overview: String?
    var genres: [String]?
    var rating: Double?                 // TMDB vote_average (0...10)

    // Details
    var runtimeMinutes: Int?            // formatted in the view via FormatStyle
    var status: String?
    var country: String?
    var language: String?
    var certification: String?          // "PG-13" / "TV-MA"

    // Credits
    var cast: [EnrichedCastMember] = []
    var directors: [String] = []
    var writers: [String] = []

    // Where to watch (US, JustWatch via TMDB). The hero badge shows the primary subscription
    // provider's logo (nil → no badge); the groups drive the "How to Watch" section; the link is
    // the aggregate JustWatch page the provider cards open.
    var providerBadgeURL: URL?
    var watchProviderGroups: [WatchProviderGroup] = []
    var watchLink: URL?

    // Discovery — "More Like This" previews (TMDB-ref encoded; resolved to IMDB on select).
    var recommendations: [MetaPreview] = []
    var trailers: [Trailer] = []
}

/// A streaming/rental/purchase service the title is available on, with its (square) logo.
struct WatchProvider: Sendable, Hashable, Identifiable {
    let id: Int
    let name: String
    let logoURL: URL?
}

/// Providers grouped by availability type, e.g. "Stream" (subscription), "Rent", "Buy".
struct WatchProviderGroup: Sendable, Hashable, Identifiable {
    var id: String { label }
    let label: String
    let providers: [WatchProvider]
}

/// A cast member with optional headshot. `character` is the role; `profileURL` may be nil.
struct EnrichedCastMember: Sendable, Hashable, Identifiable {
    let id: Int
    let name: String
    let character: String?
    let profileURL: URL?
}

/// Per-episode metadata TMDB provides that the addon often lacks.
struct EpisodeEnrichment: Sendable, Hashable {
    var title: String?
    var overview: String?
    var stillURL: URL?
    var runtimeMinutes: Int?
}

/// A playable trailer reference. Currently always a YouTube key (playback strategy decided in Stage C).
struct Trailer: Sendable, Hashable, Identifiable {
    let id: String            // YouTube key
    let title: String
    var youTubeKey: String { id }
}

extension Enrichment {
    /// Stable key for `episodeInfo` lookups.
    static func episodeKey(season: Int, episode: Int) -> String { "\(season):\(episode)" }
}
