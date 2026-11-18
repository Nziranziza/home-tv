import Foundation

/// What the timestamp databases are asked for: an IMDb id, plus the episode's numbers for a show.
struct SkipSegmentQuery: Hashable, Sendable {
    let imdbID: String
    let season: Int?
    let episode: Int?

    var isMovie: Bool { season == nil }

    /// Nil when the title has no IMDb id or an episode lacks its numbers.
    init?(type: String, item: PlaybackItem) {
        guard item.showID.wholeMatch(of: /tt[0-9]{7,}/) != nil else { return nil }
        imdbID = item.showID
        if type == "movie" {
            season = nil
            episode = nil
        } else {
            guard let season = item.season, let episode = item.episode else { return nil }
            self.season = season
            self.episode = episode
        }
    }
}
