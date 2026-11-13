import Foundation
import Testing
@testable import HomeTV

/// When the in-app player reports to Trakt, and with what progress.
@MainActor
struct PlayerScrobbleTests {

    struct Report: Equatable {
        let action: TraktScrobble.Action
        let percent: Int
    }

    @MainActor
    final class ReportLog {
        var reports: [Report] = []
    }

    static func model(
        state: PlaybackState = .playing,
        time: TimeInterval = 1390,
        duration: TimeInterval = 2820,
        item: PlaybackItem? = PlaybackItem(contentID: "tt0903747:1:4", showID: "tt0903747")
    ) throws -> (PlayerModel, FakePlaybackEngine, ReportLog) {
        let engine = FakePlaybackEngine()
        engine.state = state
        engine.currentTime = time
        engine.duration = duration
        let url = try #require(URL(string: "https://debrid.example/Episode.mkv"))
        let log = ReportLog()
        let model = PlayerModel(
            request: PlayerRequest(url: url, type: "series", title: "Breaking Bad", item: item),
            engine: engine,
            publishesNowPlaying: false,
            recordProgress: { _, _, _ in },
            scrobble: { log.reports.append(Report(action: $0.action, percent: Int(($0.fraction * 100).rounded()))) }
        )
        return (model, engine, log)
    }

    @Test func playStartsAndPausePausesWithTheStreamsOwnProgress() throws {
        let (model, engine, log) = try Self.model()
        model.playbackDidChange()
        engine.state = .paused
        engine.currentTime = 1410
        model.playbackDidChange()
        #expect(log.reports == [Report(action: .start, percent: 49), Report(action: .pause, percent: 50)])
    }

    @Test func bufferingDoesNotRestart() throws {
        let (model, engine, log) = try Self.model()
        model.playbackDidChange()
        engine.state = .buffering
        model.playbackDidChange()
        engine.state = .playing
        model.playbackDidChange()
        #expect(log.reports.map(\.action) == [.start])
    }

    @Test func closingMidwayPauses() throws {
        let (model, _, log) = try Self.model()
        model.playbackDidChange()
        model.stop()
        #expect(log.reports.map(\.action) == [.start, .pause])
    }

    @Test func closingPastTheFinishLineStops() throws {
        let (model, engine, log) = try Self.model()
        model.playbackDidChange()
        engine.currentTime = 2750
        model.stop()
        #expect(log.reports.last == Report(action: .stop, percent: 98))
    }

    @Test func playingToTheEndStopsOnceAtFullProgress() throws {
        let (model, engine, log) = try Self.model()
        model.start()
        model.playbackDidChange()
        engine.onFinish?(nil)
        model.stop()
        #expect(log.reports == [Report(action: .start, percent: 49), Report(action: .stop, percent: 100)])
    }

    @Test func backgroundingPausesAndReturningRestarts() throws {
        let (model, _, log) = try Self.model()
        model.playbackDidChange()
        model.sceneDidChange(isActive: false)
        model.sceneDidChange(isActive: false)
        model.sceneDidChange(isActive: true)
        #expect(log.reports.map(\.action) == [.start, .pause, .start])
    }

    @Test func aStreamThatNeverPlayedReportsNothing() throws {
        let (model, _, log) = try Self.model(state: .loading, time: 0)
        model.playbackDidChange()
        model.stop()
        #expect(log.reports.isEmpty)
    }

    @Test func aPlayWithoutALibraryItemReportsNothing() throws {
        let (model, _, log) = try Self.model(item: nil)
        model.playbackDidChange()
        model.stop()
        #expect(log.reports.isEmpty)
    }
}
