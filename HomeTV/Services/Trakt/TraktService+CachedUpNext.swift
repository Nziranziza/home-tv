import Foundation

extension TraktService {
    /// An up-next episode with the show's `last_watched_at` when it was fetched, so a cached entry is
    /// reused only while nothing has been watched since.
    struct CachedUpNext: Equatable, Sendable {
        let episode: EpisodeNumber
        let lastWatchedAt: Date
    }
}
