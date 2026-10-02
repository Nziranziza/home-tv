import Foundation
import Observation

/// What the user has watched, how far into it they are, and what they saved for later, kept on this
/// Apple TV. Trakt owns all of it when connected; none of it requires Trakt, and `UserLibrary` picks.
///
/// Ids are Stremio content ids, which double as the progress keys Trakt uses: `tt0903747` for a movie
/// or show, `tt0903747:1:4` for an episode.
@Observable
@MainActor
final class LocalLibrary {
    static let shared = LocalLibrary()

    private(set) var watchedIDs: Set<String> = []
    /// Fraction watched, 0...1, by content id — the same shape and keying as Trakt's playback progress.
    private(set) var progressByID: [String: Double] = [:]
    /// Newest play activity by content id, which picks the show hero's episode.
    private(set) var activityByID: [String: PlayActivity] = [:]
    /// Saved titles, newest first. Whole previews rather than ids, so the row renders without fetching.
    private(set) var watchlist: [MetaPreview] = []

    /// Outside this a title has barely started, or is finished. Mirrors Trakt's own playback window.
    static let resumeRange: ClosedRange<Double> = 0.01...0.95

    private struct Snapshot: Codable {
        var watched: [String]
        var progress: [String: Double]
        var watchlist: [MetaPreview]
        /// Optional so libraries saved before it existed still decode.
        var activity: [String: PlayActivity]?
    }

    private let storageKey = "hometv.localLibrary.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: storageKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        watchedIDs = Set(snapshot.watched)
        progressByID = snapshot.progress
        watchlist = snapshot.watchlist
        activityByID = snapshot.activity ?? [:]
    }

    /// The content id for a title, or one of its episodes. nil when unnumbered: coercing to 0 would
    /// write a record no read ever matches.
    nonisolated static func id(show: String, season: Int? = nil, episode: Int? = nil) -> String? {
        guard !show.isEmpty else { return nil }
        if season == nil, episode == nil { return show }
        guard let season, let episode else { return nil }
        return "\(show):\(season):\(episode)"
    }

    // MARK: - Watched

    func isWatched(_ id: String) -> Bool { watchedIDs.contains(id) }

    /// Marking watched counts as finishing it now, even if it already was; unmarking forgets its activity.
    func setWatched(_ watched: Bool, id: String) {
        if watched {
            watchedIDs.insert(id)
            // Finishing clears the resume point, as Trakt drops the playback entry.
            progressByID[id] = nil
            activityByID[id] = PlayActivity(date: .now, isFinished: true)
        } else {
            guard watchedIDs.remove(id) != nil else { return }
            activityByID[id] = nil
        }
        save()
    }

    func toggleWatched(id: String) { setWatched(!isWatched(id), id: id) }

    // MARK: - Progress

    func progress(forKey key: String) -> Double? { progressByID[key] }

    /// How far into a title the user got. Outside the resume window the entry is dropped; past its end
    /// the title counts as finished. A barely-started play isn't activity, so a stray open can't take over
    /// the hero.
    func setProgress(_ fraction: Double, id: String) {
        progressByID[id] = Self.resumeRange.contains(fraction) ? fraction : nil
        if fraction >= Self.resumeRange.lowerBound {
            activityByID[id] = PlayActivity(date: .now, isFinished: fraction > Self.resumeRange.upperBound)
        }
        save()
    }

    func lastPlayed(forKey key: String) -> PlayActivity? { activityByID[key] }

    // MARK: - Watchlist

    func isInWatchlist(_ id: String) -> Bool { watchlist.contains { $0.id == id } }

    func toggleWatchlist(_ preview: MetaPreview) {
        if isInWatchlist(preview.id) {
            watchlist.removeAll { $0.id == preview.id }
        } else {
            watchlist.insert(preview, at: 0)
        }
        save()
    }

    private func save() {
        let snapshot = Snapshot(watched: Array(watchedIDs), progress: progressByID, watchlist: watchlist, activity: activityByID)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
