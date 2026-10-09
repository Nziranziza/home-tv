import Foundation
import Testing
@testable import HomeTV

/// Trakt Continue Watching: paused items plus the next episode of recently watched shows (#84).
struct ContinueWatchingUpNextTests {

    // MARK: - Up-next episode

    @Test func finishedEpisodePointsAtTheNextOne() {
        let next = TraktService.upNextEpisode(in: progress([1: [1, 2, 3, 4]], watched: [(1, 1), (1, 2), (1, 3)]))
        #expect(next == .init(season: 1, episode: 4))
    }

    @Test func seasonFinaleMovesOnToTheNextSeason() {
        let next = TraktService.upNextEpisode(in: progress([1: [1, 2], 2: [1, 2]], watched: [(1, 1), (1, 2)]))
        #expect(next == .init(season: 2, episode: 1))
    }

    @Test func caughtUpShowHasNoUpNext() {
        let next = TraktService.upNextEpisode(in: progress([1: [1, 2]], watched: [(1, 1), (1, 2)]))
        #expect(next == nil)
    }

    /// Rewatching E2 after finishing E1–E4 plays E3, like the detail hero.
    @Test func lastPlayedEpisodeDecidesNotTheFurthest() {
        let next = TraktService.upNextEpisode(
            in: progress([1: [1, 2, 3, 4, 5]], watched: [(1, 1), (1, 3), (1, 4), (1, 2)])
        )
        #expect(next == .init(season: 1, episode: 3))
    }

    @Test func specialsAreIgnored() {
        let next = TraktService.upNextEpisode(in: progress([0: [1], 1: [1, 2]], watched: [(1, 1)]))
        #expect(next == .init(season: 1, episode: 2))
    }

    // MARK: - Candidates

    @Test func candidatesAreRecentShowsNotPausedSinceTheirLastWatch() {
        let shows = [watched("tt1", day: 1), watched("tt2", day: 3), watched("tt3", day: 2), watched("tt4", day: 4)]
        let ids = TraktService.upNextCandidates(
            watchedShows: shows,
            playbackEpisodes: [pausedEpisode("tt4", season: 1, episode: 1, day: 5)],
            limit: 2
        )
        #expect(ids == ["tt2", "tt3"])
    }

    // MARK: - Row

    /// A show with an episode finished after its pause still asks for up next.
    @Test func showFinishedAfterItsPauseIsACandidate() {
        let ids = TraktService.upNextCandidates(
            watchedShows: [watched("tt1", day: 3)],
            playbackEpisodes: [pausedEpisode("tt1", season: 1, episode: 1, day: 2)]
        )
        #expect(ids == ["tt1"])
    }

    @Test func pausedEpisodeWinsOverUpNext() {
        let items = TraktService.continueWatchingItems(
            playback: [pausedEpisode("tt1", season: 1, episode: 2, day: 2)],
            watchedShows: [watched("tt1", day: 1)],
            upNext: ["tt1": .init(season: 1, episode: 5)]
        )
        #expect(items.count == 1)
        #expect(items.first?.episodeKey == "tt1:1:2")
    }

    /// Paused E1, then finished E2: the card follows the detail hero to E3, not the stale pause.
    @Test func episodeFinishedAfterThePauseWins() {
        let items = TraktService.continueWatchingItems(
            playback: [pausedEpisode("tt1", season: 1, episode: 1, day: 1)],
            watchedShows: [watched("tt1", day: 2)],
            upNext: ["tt1": .init(season: 1, episode: 3)]
        )
        #expect(items.count == 1)
        #expect(items.first?.episodeKey == "tt1:1:3")
    }

    @Test func rowIsOrderedByNewestActivityAcrossMoviesAndShows() {
        let items = TraktService.continueWatchingItems(
            playback: [pausedMovie("tt9", day: 3), pausedEpisode("tt1", season: 1, episode: 1, day: 1)],
            watchedShows: [watched("tt1", day: 1), watched("tt2", day: 4), watched("tt3", day: 2)],
            upNext: ["tt2": .init(season: 2, episode: 4), "tt3": .init(season: 1, episode: 2)]
        )
        #expect(items.map(\.metaID) == ["tt2", "tt9", "tt3", "tt1"])
        #expect(items.first?.episodeKey == "tt2:2:4")
        #expect(items[1].episodeKey == nil)
    }

    @Test func caughtUpShowIsLeftOut() {
        let items = TraktService.continueWatchingItems(
            playback: [],
            watchedShows: [watched("tt1", day: 1)],
            upNext: [:]
        )
        #expect(items.isEmpty)
    }

    // MARK: - Fixtures

    private func progress(_ seasons: [Int: [Int]], watched: [(Int, Int)]) -> TraktShowProgress {
        // Watch order sets `last_watched_at`: later in the list is newer.
        var watchedAt: [String: String] = [:]
        for (index, entry) in watched.enumerated() {
            watchedAt["\(entry.0):\(entry.1)"] = timestamp(day: index + 1)
        }
        return TraktShowProgress(
            aired: nil,
            completed: nil,
            seasons: seasons.keys.sorted().map { season in
                TraktProgressSeason(
                    number: season,
                    episodes: (seasons[season] ?? []).map { number in
                        let stamp = watchedAt["\(season):\(number)"]
                        return TraktProgressEpisode(number: number, completed: stamp != nil, lastWatchedAt: stamp)
                    }
                )
            }
        )
    }

    private func watched(_ imdb: String, day: Int) -> TraktWatchedShow {
        TraktWatchedShow(show: show(imdb), lastWatchedAt: timestamp(day: day))
    }

    private func pausedEpisode(_ imdb: String, season: Int, episode: Int, day: Int) -> TraktPlaybackItem {
        TraktPlaybackItem(
            progress: 40,
            pausedAt: timestamp(day: day),
            type: "episode",
            movie: nil,
            episode: TraktEpisode(season: season, number: episode, title: nil, ids: nil, runtime: nil),
            show: show(imdb)
        )
    }

    private func pausedMovie(_ imdb: String, day: Int) -> TraktPlaybackItem {
        TraktPlaybackItem(
            progress: 40,
            pausedAt: timestamp(day: day),
            type: "movie",
            movie: TraktMovie(title: imdb, year: nil, ids: ids(imdb), runtime: nil),
            episode: nil,
            show: nil
        )
    }

    private func show(_ imdb: String) -> TraktShow {
        TraktShow(title: imdb, year: nil, ids: ids(imdb))
    }

    private func ids(_ imdb: String) -> TraktIDs {
        TraktIDs(trakt: nil, slug: nil, imdb: imdb, tmdb: nil)
    }

    private func timestamp(day: Int) -> String {
        "2026-10-\(day < 10 ? "0" : "")\(day)T12:00:00.000Z"
    }
}
