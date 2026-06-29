import Foundation

/// The Trailerio addon (`io.trailerio.lite`) answers a standard Stremio `meta` request but packs the
/// trailers into a non-standard `meta.links` array — each entry is `{ trailers: <direct url>, provider:
/// <name> }`, where the url is a directly playable mp4 / HLS stream (NOT a YouTube id). That shape
/// doesn't fit the shared `Meta`/`MetaResponse`, so it gets its own lightweight decode.
struct TrailerioMetaResponse: Codable, Sendable {
    let meta: TrailerioMeta
}

struct TrailerioMeta: Codable, Sendable {
    let id: String
    let type: String?
    let name: String?
    let links: [TrailerioLink]?
}

struct TrailerioLink: Codable, Sendable {
    /// A directly playable trailer URL (mp4 or HLS `.m3u8`).
    let trailers: String
    /// Human-facing source label, e.g. "Apple TV 1080p 5.1", "⭐ Plex 1080p".
    let provider: String?
}
