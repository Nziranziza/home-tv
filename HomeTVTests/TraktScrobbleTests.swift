import Foundation
import Testing
@testable import HomeTV

/// The scrobble request bodies, how a play ends on Trakt, and the Continue Watching row after a scrobble.
@MainActor
struct TraktScrobbleTests {

    static let episode = PlaybackItem(contentID: "tt0903747:1:4", showID: "tt0903747")
    static let movie = PlaybackItem(contentID: "tt0133093", showID: "tt0133093")

    static func scrobble(_ action: TraktScrobble.Action, _ item: PlaybackItem, fraction: Double = 0.5) -> TraktScrobble {
        TraktScrobble(action: action, item: item, type: item == movie ? "movie" : "series", title: "Title", fraction: fraction)
    }

    static func json(_ scrobble: TraktScrobble) throws -> [String: Any] {
        let body = try #require(scrobble.body)
        return try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    @Test func anEpisodeIsSentAsItsShowWithSeasonAndNumber() throws {
        let object = try Self.json(Self.scrobble(.pause, Self.episode, fraction: 0.4912))
        let show = try #require(object["show"] as? [String: Any])
        #expect((show["ids"] as? [String: String])?["imdb"] == "tt0903747")
        let episode = try #require(object["episode"] as? [String: Int])
        #expect(episode == ["season": 1, "number": 4])
        #expect(object["progress"] as? Double == 49.12)
        #expect(object["movie"] == nil)
    }

    @Test func aMovieIsSentByItsID() throws {
        let object = try Self.json(Self.scrobble(.start, Self.movie, fraction: 1))
        let movie = try #require(object["movie"] as? [String: Any])
        #expect((movie["ids"] as? [String: String])?["imdb"] == "tt0133093")
        #expect(object["progress"] as? Double == 100)
        #expect(object["show"] == nil)
    }

    @Test func titlesTraktCantIdentifyAreNotSent() {
        let kitsu = PlaybackItem(contentID: "kitsu:1234:5", showID: "kitsu:1234")
        let unnumbered = PlaybackItem(contentID: "tt0903747:abc", showID: "tt0903747")
        #expect(Self.scrobble(.pause, kitsu).body == nil)
        #expect(Self.scrobble(.pause, unnumbered).body == nil)
    }

    @Test func onlyAFinishedPlayEndsWithStop() {
        #expect(TraktScrobble.endAction(forFraction: 0.5) == .pause)
        // Trakt would add history from 80%; locally that's still a resume point.
        #expect(TraktScrobble.endAction(forFraction: 0.9) == .pause)
        #expect(TraktScrobble.endAction(forFraction: 0.96) == .stop)
    }

    static func card(_ id: String, type: String = "series", season: Int? = nil, episode: Int? = nil, at date: Date) -> WatchHistoryItem {
        var item = WatchHistoryItem(preview: TraktService.preview(imdb: id, type: type, name: "Kept \(id)"), viewedAt: date)
        item.season = season
        item.episode = episode
        return item
    }

    @Test func aPauseMovesItsShowFirstOnThePausedEpisode() {
        let old = Date(timeIntervalSince1970: 0)
        let now = Date(timeIntervalSince1970: 100)
        let row = [
            Self.card("tt0000001", at: old),
            Self.card("tt0903747", season: 1, episode: 3, at: old)
        ]
        let updated = TraktService.continueWatchingItems(row, after: Self.scrobble(.pause, Self.episode), at: now)
        #expect(updated.map(\.metaID) == ["tt0903747", "tt0000001"])
        #expect(updated[0].episodeKey == "tt0903747:1:4")
        #expect(updated[0].viewedAt == now)
        // The existing card's name is kept over the player's title.
        #expect(updated[0].name == "Kept tt0903747")
    }

    @Test func aPauseOfANewTitleAddsItsCard() {
        let updated = TraktService.continueWatchingItems([], after: Self.scrobble(.pause, Self.movie))
        #expect(updated.map(\.metaID) == ["tt0133093"])
        #expect(updated.first?.typeID == "movie")
        #expect(updated.first?.name == "Title")
    }

    @Test func aFinishedMovieLeavesTheRow() {
        let row = [Self.card("tt0133093", type: "movie", at: .now)]
        #expect(TraktService.continueWatchingItems(row, after: Self.scrobble(.stop, Self.movie, fraction: 1)).isEmpty)
    }

    @Test func aFinishedEpisodeWaitsForTheSyncToBringUpNext() {
        let row = [Self.card("tt0903747", season: 1, episode: 4, at: .now)]
        let updated = TraktService.continueWatchingItems(row, after: Self.scrobble(.stop, Self.episode, fraction: 1))
        #expect(updated == row)
    }
}
