import Foundation

/// One in-app player report for Trakt's `/scrobble/*` endpoints.
struct TraktScrobble: Equatable, Sendable {
    enum Action: String, Sendable {
        case start, pause, stop
    }

    let action: Action
    let item: PlaybackItem
    /// The Stremio type, `movie` or `series`.
    let type: String
    /// The movie's or show's name, for a Continue Watching card Trakt hasn't sent yet.
    let title: String
    /// 0...1 of the stream's own duration.
    let fraction: Double

    /// How a play ends: `stop` only once it's finished, since Trakt adds a history entry for a `stop`
    /// at 80% or more. Anything short of our own finish line is a `pause`, which only saves progress.
    @MainActor static func endAction(forFraction fraction: Double) -> Action {
        fraction > LocalLibrary.resumeRange.upperBound ? .stop : .pause
    }

    var isMovie: Bool { item.season == nil && item.episode == nil && item.contentID == item.showID }

    /// The `TraktService.playbackProgress` key: the movie's id, or `imdb:season:episode`.
    var progressKey: String {
        guard let season = item.season, let episode = item.episode else { return item.showID }
        return "\(item.showID):\(season):\(episode)"
    }

    /// The request body, or nil for a title Trakt can't identify: no IMDB id, or an unnumbered episode.
    var body: Data? {
        guard item.showID.hasPrefix("tt") else { return nil }
        let progress = (min(max(fraction, 0), 1) * 100 * 100).rounded() / 100
        var object: [String: Any] = ["progress": progress]
        if isMovie {
            object["movie"] = ["ids": ["imdb": item.showID]]
        } else {
            guard let season = item.season, let episode = item.episode else { return nil }
            object["show"] = ["ids": ["imdb": item.showID]]
            object["episode"] = ["season": season, "number": episode]
        }
        return try? JSONSerialization.data(withJSONObject: object)
    }
}
