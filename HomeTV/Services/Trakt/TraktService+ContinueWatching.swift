import Foundation

/// Continue Watching rules: paused movies and episodes, plus the next episode of recently watched shows.
/// Pure and `nonisolated` so the library sync runs them off the main actor.
extension TraktService {
    struct EpisodeNumber: Hashable, Sendable {
        let season: Int
        let episode: Int
    }

    /// Upper bound on show progress requests per sync.
    nonisolated static let upNextShowLimit = 10
    /// How long the sync waits for up-next before applying without the stragglers.
    nonisolated static let upNextDeadline: Duration = .seconds(8)

    /// Shows to ask for an up-next episode, most recently watched first. A show paused after its last
    /// finished episode is skipped, since that paused episode takes its card.
    nonisolated static func upNextCandidates(
        watchedShows: [TraktWatchedShow],
        playbackEpisodes: [TraktPlaybackItem],
        limit: Int = upNextShowLimit
    ) -> [String] {
        let pausedAt = latestPausedAt(playbackEpisodes)
        let recent = watchedShows
            .compactMap { watched -> (id: String, date: Date)? in
                guard let id = watched.show.ids.imdb,
                      let date = date(fromISO8601: watched.lastWatchedAt) else { return nil }
                return (id, date)
            }
            .filter { show in pausedAt[show.id].map { $0 < show.date } ?? true }
            .sorted { $0.date > $1.date }
        return recent.prefix(limit).map(\.id)
    }

    /// Up-next episodes for the candidate shows. A show whose request fails or misses the deadline keeps
    /// its `previous` episode; a caught-up show is dropped.
    nonisolated static func loadUpNext(
        watchedShows: [TraktWatchedShow],
        playbackEpisodes: [TraktPlaybackItem],
        previous: [String: EpisodeNumber],
        token: String
    ) async -> [String: EpisodeNumber] {
        let showIDs = upNextCandidates(watchedShows: watchedShows, playbackEpisodes: playbackEpisodes)
        let fetched = await fetchUpNext(showIDs: showIDs, token: token)
        var result: [String: EpisodeNumber] = [:]
        for showID in showIDs {
            result[showID] = fetched[showID] ?? previous[showID]
        }
        return result
    }

    /// The aired episode after the last played one, like the detail hero's up-next. nil when caught up.
    nonisolated static func upNextEpisode(in progress: TraktShowProgress) -> EpisodeNumber? {
        let episodes = progress.seasons
            .filter { $0.number > 0 }
            .sorted { $0.number < $1.number }
            .flatMap { season in
                season.episodes
                    .sorted { $0.number < $1.number }
                    .map { (season: season.number, episode: $0) }
            }

        var last: (index: Int, date: Date)?
        for (index, entry) in episodes.enumerated() where entry.episode.completed {
            // `>=` so a tie goes to the later episode.
            guard let date = date(fromISO8601: entry.episode.lastWatchedAt),
                  date >= last?.date ?? .distantPast else { continue }
            last = (index, date)
        }
        // No timestamps: continue after the furthest watched.
        guard let anchor = last?.index ?? episodes.lastIndex(where: \.episode.completed),
              anchor + 1 < episodes.count else { return nil }
        let next = episodes[anchor + 1]
        return EpisodeNumber(season: next.season, episode: next.episode.number)
    }

    /// Fetched up-next per show, in parallel, until `upNextDeadline`. An inner nil means caught up; a
    /// missing key means the request failed or ran out of time.
    nonisolated private static func fetchUpNext(showIDs: [String], token: String) async -> [String: EpisodeNumber?] {
        enum Outcome: Sendable {
            case fetched(String, EpisodeNumber?)
            case failed
            case deadline
        }
        return await withTaskGroup(of: Outcome.self) { group in
            for showID in showIDs {
                group.addTask {
                    guard let progress = try? await TraktClient.shared.showProgress(imdb: showID, token: token) else {
                        return .failed
                    }
                    return .fetched(showID, upNextEpisode(in: progress))
                }
            }
            group.addTask {
                try? await Task.sleep(for: upNextDeadline)
                return .deadline
            }
            var result: [String: EpisodeNumber?] = [:]
            var pending = showIDs.count
            while pending > 0, let outcome = await group.next() {
                switch outcome {
                case .fetched(let showID, let next):
                    result[showID] = .some(next)
                    pending -= 1
                case .failed:
                    pending -= 1
                case .deadline:
                    pending = 0
                }
            }
            group.cancelAll()
            return result
        }
    }

    /// The row, newest activity first. A show appears once, on its last played episode like the detail
    /// hero: a paused episode wins over up next unless an episode was finished after it.
    /// `playback` is movies and episodes ordered by `paused_at`, newest first.
    nonisolated static func continueWatchingItems(
        playback: [TraktPlaybackItem],
        watchedShows: [TraktWatchedShow],
        upNext: [String: EpisodeNumber]
    ) -> [WatchHistoryItem] {
        var lastWatchedAt: [String: Date] = [:]
        for watched in watchedShows {
            guard let showID = watched.show.ids.imdb,
                  let date = date(fromISO8601: watched.lastWatchedAt) else { continue }
            lastWatchedAt[showID] = date
        }

        var items: [WatchHistoryItem] = []
        var seen = Set<String>()
        for item in playback {
            let pausedAt = date(fromISO8601: item.pausedAt) ?? .distantPast
            if item.type == "movie", let id = item.movie?.ids.imdb {
                guard seen.insert(id).inserted else { continue }
                items.append(continueItem(imdb: id, type: "movie", name: item.movie?.title, episode: nil, activity: pausedAt))
            } else if let showID = item.show?.ids.imdb,
                      let season = item.episode?.season,
                      let number = item.episode?.number {
                guard pausedAt >= lastWatchedAt[showID] ?? .distantPast,
                      seen.insert(showID).inserted else { continue }
                items.append(continueItem(
                    imdb: showID,
                    type: "series",
                    name: item.show?.title,
                    episode: EpisodeNumber(season: season, episode: number),
                    activity: pausedAt
                ))
            }
        }
        for watched in watchedShows {
            guard let showID = watched.show.ids.imdb,
                  let next = upNext[showID],
                  seen.insert(showID).inserted else { continue }
            items.append(continueItem(
                imdb: showID,
                type: "series",
                name: watched.show.title,
                episode: next,
                activity: lastWatchedAt[showID] ?? .distantPast
            ))
        }
        return items.sorted { $0.viewedAt > $1.viewedAt }
    }

    nonisolated private static func latestPausedAt(_ playbackEpisodes: [TraktPlaybackItem]) -> [String: Date] {
        var result: [String: Date] = [:]
        for item in playbackEpisodes {
            guard let showID = item.show?.ids.imdb, let date = date(fromISO8601: item.pausedAt) else { continue }
            result[showID] = max(result[showID] ?? .distantPast, date)
        }
        return result
    }

    nonisolated private static func continueItem(
        imdb: String,
        type: String,
        name: String?,
        episode: EpisodeNumber?,
        activity: Date
    ) -> WatchHistoryItem {
        var item = WatchHistoryItem(preview: preview(imdb: imdb, type: type, name: name ?? ""), viewedAt: activity)
        item.season = episode?.season
        item.episode = episode?.episode
        return item
    }
}
