import CoreGraphics
import Foundation
import Testing
@testable import HomeTV

/// Fast-forward and rewind: the level ladder, the scan's clock, commit and cancel.
@MainActor
struct PlayerScanTests {

    /// A clock the tests move by hand.
    final class Clock {
        var now = ContinuousClock.now
        func advance(_ seconds: Double) { now = now.advanced(by: .seconds(seconds)) }
    }

    static func model(
        state: PlaybackState = .playing,
        time: TimeInterval = 1000,
        duration: TimeInterval = 7200
    ) throws -> (PlayerModel, FakePlaybackEngine, Clock) {
        let engine = FakePlaybackEngine()
        engine.state = state
        engine.currentTime = time
        engine.duration = duration
        let clock = Clock()
        let url = try #require(URL(string: "https://debrid.example/Movie.mkv"))
        let model = PlayerModel(
            request: PlayerRequest(url: url),
            engine: engine,
            publishesNowPlaying: false,
            makeThumbnailer: { _ in StubThumbnailer() },
            now: { clock.now }
        )
        return (model, engine, clock)
    }

    // MARK: - Ladder

    @Test func sameSideClimbsAndStaysAtTheTop() {
        var scan = PlayerScan(direction: .forward)
        #expect(scan.rate == 8)
        scan.click(.forward)
        #expect(scan.rate == 24)
        scan.click(.forward)
        #expect(scan.rate == 48)
        scan.click(.forward)
        #expect(scan.rate == 96)
        scan.click(.forward)
        #expect(scan.level == 4)
        #expect(scan.rate == 96)
    }

    @Test func otherSideStepsDownThenReverses() {
        var scan = PlayerScan(direction: .forward)
        scan.click(.forward)
        scan.click(.forward)
        scan.click(.backward)
        #expect(scan.level == 2)
        scan.click(.backward)
        #expect(scan.level == 1)
        #expect(scan.direction == .forward)
        scan.click(.backward)
        #expect(scan.direction == .backward)
        #expect(scan.level == 1)
        #expect(scan.rate == -8)
        scan.click(.backward)
        #expect(scan.rate == -24)
    }

    // MARK: - Clock

    @Test func scanMovesAtItsSpeedAndStopsAtTheEnds() {
        let start = ContinuousClock.now
        var scrub = PlayerScrub(
            origin: 100,
            duration: 1000,
            isFromPlayback: true,
            scan: PlayerScan(direction: .forward),
            at: start
        )
        #expect(scrub.position(at: start.advanced(by: .seconds(2))) == 116)
        scrub.click(.forward, at: start.advanced(by: .seconds(2)))
        #expect(scrub.position(at: start.advanced(by: .seconds(3))) == 140)
        #expect(scrub.position(at: start.advanced(by: .seconds(100))) == 1000)
        scrub.click(.backward, at: start.advanced(by: .seconds(3)))
        scrub.click(.backward, at: start.advanced(by: .seconds(3)))
        #expect(scrub.scan?.rate == -8)
        #expect(scrub.position(at: start.advanced(by: .seconds(1000))) == 0)
    }

    // MARK: - From playback

    @Test func holdFromPlaybackPausesTheEngineAndFollowsTheFill() throws {
        let (model, engine, clock) = try Self.model()
        model.arrowHeld(.forward)
        #expect(engine.state == .paused)
        #expect(model.timeIndicator == .scan(PlayerScan(direction: .forward)))
        clock.advance(10)
        #expect(model.displayTime == 1080)
        #expect(model.fillTime == 1080)
        #expect(model.bar.isVisible)
    }

    @Test func clicksDuringAScanChangeTheLevelInsteadOfSkipping() throws {
        let (model, engine, _) = try Self.model()
        #expect(!model.arrowPressed(.forward))
        model.arrowHeld(.forward)
        #expect(model.arrowPressed(.forward))
        #expect(model.scrub?.scan?.level == 2)
        #expect(engine.seeks.isEmpty)
    }

    @Test func selectPlaysFromTheScanAndHidesTheBar() throws {
        let (model, engine, clock) = try Self.model()
        model.arrowHeld(.backward)
        clock.advance(5)
        model.togglePlayPause()
        #expect(engine.seeks == [960])
        #expect(engine.state == .playing)
        #expect(model.scrub == nil)
        #expect(!model.bar.isVisible)
    }

    @Test func playPauseFromPlaybackAlsoCommits() throws {
        let (model, engine, clock) = try Self.model()
        model.arrowHeld(.forward)
        clock.advance(1)
        model.playPauseCommand()
        #expect(engine.seeks == [1008])
        #expect(engine.state == .playing)
    }

    @Test func menuCancelsToTheExactStartAndKeepsPlaying() throws {
        let (model, engine, clock) = try Self.model()
        model.arrowHeld(.forward)
        clock.advance(20)
        #expect(model.handleExit())
        #expect(model.scrub == nil)
        #expect(engine.seeks.isEmpty)
        #expect(engine.currentTime == 1000)
        #expect(engine.state == .playing)
    }

    @Test func nowPlayingSeekDuringAScanFromPlaybackResumes() throws {
        let (model, engine, _) = try Self.model()
        model.arrowHeld(.forward)
        model.seek(to: 500)
        #expect(model.scrub == nil)
        #expect(engine.seeks == [500])
        #expect(engine.state == .playing)
    }

    // MARK: - From pause

    @Test func pausedScanKeepsTheFillAtPlayback() throws {
        let (model, engine, clock) = try Self.model(state: .paused)
        model.arrowHeld(.forward)
        clock.advance(5)
        #expect(model.displayTime == 1040)
        #expect(model.fillTime == 1000)
        #expect(engine.state == .paused)
    }

    @Test func playPauseStopsAPausedScanAndStaysThere() throws {
        let (model, engine, clock) = try Self.model(state: .paused)
        model.arrowHeld(.forward)
        clock.advance(5)
        model.playPauseCommand()
        clock.advance(5)
        #expect(model.scrub?.scan == nil)
        #expect(model.displayTime == 1040)
        #expect(engine.state == .paused)
        #expect(model.timeIndicator == .paused)
        model.playPauseCommand()
        #expect(engine.seeks == [1040])
        #expect(engine.state == .playing)
    }

    @Test func firstMenuStopsAPausedScanSecondCancels() throws {
        let (model, engine, clock) = try Self.model(state: .paused)
        model.arrowHeld(.backward)
        clock.advance(5)
        #expect(model.handleExit())
        #expect(model.scrub?.scan == nil)
        #expect(model.displayTime == 960)
        #expect(model.handleExit())
        #expect(model.scrub == nil)
        #expect(engine.seeks.isEmpty)
        #expect(engine.state == .playing)
    }

    @Test func holdAfterASwipeScansFromTheSwipe() throws {
        let (model, _, clock) = try Self.model(state: .paused)
        model.scrub(byPadFraction: 0.5)
        model.arrowHeld(.forward)
        clock.advance(1)
        #expect(model.displayTime == 1038)
        #expect(model.scrub?.origin == 1000)
    }

    @Test func voiceOverHearsTheScanDirectionAndLevel() {
        var scan = PlayerScan(direction: .backward)
        scan.click(.backward)
        scan.click(.backward)
        #expect(PlayerTimeIndicator.scan(scan).spokenDescription == "Rewind, speed 3")
        #expect(PlayerTimeIndicator.paused.spokenDescription == "Paused")
    }

    // MARK: - Swipe

    @Test func fasterSwipesCoverMore() {
        let slow = SwipeScrub.seconds(forFraction: 0.1, speed: 0.3, duration: 7200)
        let fast = SwipeScrub.seconds(forFraction: 0.1, speed: 3, duration: 7200)
        #expect(slow == 6)
        #expect(fast > slow * 10)
        #expect(SwipeScrub.seconds(forFraction: 1, speed: 100, duration: 7200) == 3600)
    }

    // MARK: - Thumbnails

    @Test func thumbnailsSnapToFifteenSeconds() {
        #expect(PlayerThumbnails.gridIndex(for: 44.9) == 2)
        #expect(PlayerThumbnails.gridIndex(for: 45) == 3)
        #expect(PlayerThumbnails.gridIndex(for: -3) == 0)
    }
}
