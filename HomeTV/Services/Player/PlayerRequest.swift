import Foundation

/// One in-app playback: the stream, the headers its host needs, where to start, and what to show while
/// it loads.
struct PlayerRequest: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    /// The Stremio type, `movie` or `series`, for the Info tab's meta and its Go to button.
    var type = "movie"
    /// The movie's or the show's name.
    var title = ""
    /// For an episode, `S2, E1 • The Engineer`, shown above `title`.
    var episodeLabel: String?
    var logoURL: URL?
    var headers: [String: String] = [:]
    /// Seconds to start at; 0 plays from the beginning.
    var startTime: TimeInterval = 0
    /// What to save the position against. nil plays without saving.
    var item: PlaybackItem?
    /// The add-on's subtitle files for this stream.
    var subtitles: [ExternalSubtitle] = []
    /// What the subtitle timing is remembered against; nil keeps it for this play only.
    var subtitleDelayKey: String?

    /// The same playback, whichever launch built it.
    func isSamePlay(as other: PlayerRequest) -> Bool {
        url == other.url && type == other.type && title == other.title && episodeLabel == other.episodeLabel
            && logoURL == other.logoURL && headers == other.headers && startTime == other.startTime
            && item == other.item && subtitles == other.subtitles && subtitleDelayKey == other.subtitleDelayKey
    }
}
