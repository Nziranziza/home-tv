import Foundation

/// One in-app playback: the stream, the headers its host needs, where to start, and what to show while
/// it loads.
struct PlayerRequest: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    /// The movie's or the show's name.
    var title = ""
    /// For an episode, `S2, E1 • The Engineer`, shown above `title`.
    var episodeLabel: String?
    var logoURL: URL?
    var headers: [String: String] = [:]
    /// Seconds to start at; 0 plays from the beginning.
    var startTime: TimeInterval = 0
}
