import Foundation

/// One playable trailer source for a title. Trailerio returns several (Apple TV, Plex, MUBI, IMDb …)
/// for the same clip; we keep them as an ordered list so the player can fall through to the next when
/// one fails to play (e.g. IMDb's signed URLs expire). Identity is the URL, so `id` is stable across
/// reorders and dedup.
struct TrailerCandidate: Identifiable, Hashable, Sendable {
    let url: URL
    let provider: String

    var id: String { url.absoluteString }
}
