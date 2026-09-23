import Foundation

/// An ordered season hand-off. `entries.first` is the episode the user chose.
///
/// The order is rotated rather than natural because Infuse's URL scheme has no start index: playback
/// begins at the first `url`, so the selected episode has to lead. The earlier episodes of the season
/// follow the finale, at the tail.
struct PlaybackQueue: Hashable, Sendable {
    /// The show's id (an IMDB id for Cinemeta-backed content), used to reconcile watch state.
    let showID: String
    let showName: String
    let entries: [PlaybackQueueEntry]

    var first: PlaybackQueueEntry? { entries.first }
    var isEmpty: Bool { entries.isEmpty }

    /// Position of the entry the player came back on. The exact URL is tried first; failing that (a
    /// debrid link can return with a refreshed token) entries are compared without their query, but
    /// only when exactly one matches — reconciling to the wrong one marks the wrong episodes watched.
    func index(ofEntryMatching url: URL) -> Int? {
        if let exact = entries.firstIndex(where: { $0.url == url }) { return exact }
        let target = Self.withoutQuery(url)
        let matches = entries.indices.filter { Self.withoutQuery(entries[$0].url) == target }
        return matches.count == 1 ? matches[0] : nil
    }

    /// Scheme and host lowercased, being case-insensitive; the path is not, so it is left alone.
    private static func withoutQuery(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.query = nil
        components.fragment = nil
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        return components.url?.absoluteString ?? url.absoluteString
    }
}
