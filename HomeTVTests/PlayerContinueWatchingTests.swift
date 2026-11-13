import Foundation
import Testing
@testable import HomeTV

/// The player's Continue Watching tab: its cards, its panel, and the cards' label.
@MainActor
struct PlayerContinueWatchingTests {
    private static func entry(_ type: String, _ id: String) -> WatchHistoryItem {
        WatchHistoryItem(typeID: type, metaID: id, name: id, poster: nil, background: nil, logo: nil, viewedAt: .now)
    }

    private static func model(item: PlaybackItem?, items: [WatchHistoryItem]) throws -> PlayerModel {
        let url = try #require(URL(string: "https://debrid.example/Show.mp4"))
        return PlayerModel(
            request: PlayerRequest(url: url, title: "Show", item: item),
            engine: FakePlaybackEngine(),
            bar: PlayerBarController(),
            publishesNowPlaying: false,
            recordProgress: { _, _, _ in },
            loadTitleInfo: { _, _ in nil },
            loadContinueWatching: { items }
        )
    }

    // MARK: - Cards

    @Test func leavesOutTheTitlePlaying() throws {
        let items = [Self.entry("series", "tt1"), Self.entry("movie", "tt2")]
        let model = try Self.model(item: PlaybackItem(contentID: "tt1:2:4", showID: "tt1"), items: items)
        #expect(model.continueWatchingItems.map(\.metaID) == ["tt2"])
    }

    @Test func keepsEveryCardWithoutALibraryTitle() throws {
        let items = [Self.entry("series", "tt1"), Self.entry("movie", "tt2")]
        #expect(try Self.model(item: nil, items: items).continueWatchingItems.count == 2)
    }

    // MARK: - Panel

    @Test func focusOnTheTabOrACardKeepsTheRowUp() throws {
        let model = try Self.model(item: nil, items: [])
        model.bar.show(isPlaying: true)
        model.focusDidChange(to: .continueWatching)
        #expect(model.panel == .continueWatching)
        model.focusDidChange(to: .continueWatchingCard("movie:tt2"))
        #expect(model.panel == .continueWatching)
        model.focusDidChange(to: .info)
        #expect(model.panel == .info)
        model.focusDidChange(to: .scrubber)
        #expect(model.panel == nil)
    }

    @Test func menuClosesTheRowBeforeTheBar() throws {
        let model = try Self.model(item: nil, items: [])
        model.bar.show(isPlaying: true)
        model.focusDidChange(to: .continueWatchingCard("movie:tt2"))
        #expect(model.handleExit())
        #expect(model.panel == nil)
        #expect(model.bar.isVisible)
    }

    // MARK: - Label

    @Test func episodeWithTimeLeft() {
        let text = ContinueWatchingLabel.text(season: 1, episode: 2, secondsLeft: 900, fraction: 0.6)
        #expect(text == "S1, E2 · 15m")
    }

    @Test func episodeWithoutTimeLeft() {
        #expect(ContinueWatchingLabel.text(season: 1, episode: 2, secondsLeft: nil, fraction: 0.6) == "S1, E2")
    }

    @Test func movieShowsHoursAndMinutesLeft() {
        #expect(ContinueWatchingLabel.text(season: nil, episode: nil, secondsLeft: 7740, fraction: 0.2) == "2h 9m")
    }

    @Test func percentageWhenOnlyTheFractionIsKnown() {
        #expect(ContinueWatchingLabel.text(season: nil, episode: nil, secondsLeft: nil, fraction: 0.42) == "42% watched")
        #expect(ContinueWatchingLabel.text(season: nil, episode: nil, secondsLeft: nil, fraction: nil) == nil)
    }

    @Test func underAMinuteLeftReadsOneMinute() {
        #expect(ContinueWatchingLabel.timeText(seconds: 10) == "1m")
    }
}
