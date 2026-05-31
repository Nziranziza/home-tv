import Foundation

// Trakt API payloads. The TraktClient decodes these with `.convertFromSnakeCase`, so Swift property
// names are camelCase counterparts of Trakt's snake_case JSON (e.g. `verification_url` →
// `verificationUrl`). Lenient like the Stremio models — fields we don't use are simply omitted.

/// OAuth tokens. Decoded from Trakt on sign-in/refresh, then persisted to the Keychain as-is. Network
/// decode maps snake_case → these names; persistence round-trips them with a default encoder/decoder,
/// so the camelCase property names are the single source of truth either way.
struct TraktTokens: Codable, Sendable, Equatable {
    var accessToken: String
    var refreshToken: String
    var createdAt: Int      // unix seconds (Trakt `created_at`)
    var expiresIn: Int      // seconds (Trakt `expires_in`)

    /// Trakt access tokens last ~3 months. Treat as expired a day early so `ensureValidToken()`
    /// refreshes proactively rather than mid-request.
    var isExpired: Bool {
        let expiry = Date(timeIntervalSince1970: TimeInterval(createdAt + expiresIn))
        return Date() >= expiry.addingTimeInterval(-86_400)
    }
}

struct TraktDeviceCode: Codable, Sendable {
    let deviceCode: String
    let userCode: String
    let verificationUrl: String
    let expiresIn: Int
    let interval: Int
}

struct TraktUser: Codable, Sendable, Hashable {
    let username: String
    let name: String?
}

struct TraktIDs: Codable, Sendable, Hashable {
    let trakt: Int?
    let slug: String?
    let imdb: String?
    let tmdb: Int?
}

struct TraktMovie: Codable, Sendable, Hashable {
    let title: String?
    let year: Int?
    let ids: TraktIDs
}

struct TraktShow: Codable, Sendable, Hashable {
    let title: String?
    let year: Int?
    let ids: TraktIDs
}

struct TraktEpisode: Codable, Sendable, Hashable {
    let season: Int?
    let number: Int?
    let title: String?
    let ids: TraktIDs?
}

// MARK: - Sync responses

struct TraktWatchedMovie: Codable, Sendable {
    let movie: TraktMovie
}

struct TraktWatchedShow: Codable, Sendable {
    let show: TraktShow
    let seasons: [TraktWatchedSeason]?
}

struct TraktWatchedSeason: Codable, Sendable {
    let number: Int
    let episodes: [TraktWatchedEpisode]
}

struct TraktWatchedEpisode: Codable, Sendable {
    let number: Int
}

struct TraktWatchlistMovie: Codable, Sendable {
    let movie: TraktMovie
}

struct TraktWatchlistShow: Codable, Sendable {
    let show: TraktShow
}

/// One in-progress item from `/sync/playback`. `progress` is 0–100; `type` is "movie" or "episode"
/// and the matching object below is populated. For episodes the parent `show` carries the IMDB id.
struct TraktPlaybackItem: Codable, Sendable {
    let progress: Double
    let pausedAt: String?     // Trakt `paused_at`, ISO-8601 — used to order Continue Watching
    let type: String
    let movie: TraktMovie?
    let episode: TraktEpisode?
    let show: TraktShow?
}
