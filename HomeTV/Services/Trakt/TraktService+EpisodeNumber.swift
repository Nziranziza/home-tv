import Foundation

extension TraktService {
    /// A season and episode number, the episode a Continue Watching card plays.
    struct EpisodeNumber: Hashable, Sendable {
        let season: Int
        let episode: Int
    }
}
