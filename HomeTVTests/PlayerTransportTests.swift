import Foundation
import Testing
@testable import HomeTV

/// The transport bar's clock, skip, scrub, Menu and auto-hide rules.
@MainActor
struct PlayerTransportTests {

    static func model(
        state: PlaybackState = .playing,
        time: TimeInterval = 100,
        duration: TimeInterval = 4574,
        hideDelay: Duration = .seconds(5)
    ) throws -> (PlayerModel, FakePlaybackEngine) {
        let engine = FakePlaybackEngine()
        engine.state = state
        engine.currentTime = time
        engine.duration = duration
        let url = try #require(URL(string: "https://debrid.example/Movie.mp4"))
        let model = PlayerModel(
            request: PlayerRequest(url: url),
            engine: engine,
            bar: PlayerBarController(hideDelay: hideDelay),
            publishesNowPlaying: false
        )
        return (model, engine)
    }

    // MARK: - Settings

    @Test func manageStylesWhileLoadingPausesOncePlaybackStarts() throws {
        let (model, engine) = try Self.model(state: .loading)
        model.pauseForSettings()
        engine.state = .playing
        model.playbackDidChange()
        #expect(engine.state == .paused)
    }

    // MARK: - Clock

    @Test func timesUnderAnHourPadMinutes() {
        #expect(PlayerTime.elapsed(100) == "01:40")
        #expect(PlayerTime.elapsed(0) == "00:00")
        #expect(PlayerTime.elapsed(59.9) == "00:59")
    }

    @Test func timesFromAnHourShowHours() {
        #expect(PlayerTime.remaining(4474) == "-1:14:34")
        #expect(PlayerTime.elapsed(3600) == "1:00:00")
    }

    @Test func invalidTimesReadZero() {
        #expect(PlayerTime.elapsed(.nan) == "00:00")
        #expect(PlayerTime.elapsed(-5) == "00:00")
    }

    // MARK: - Episode line

    @Test func episodeLineNamesSeasonEpisodeAndTitle() {
        #expect(PlayerEpisodeLabel.text(season: 2, episode: 1, title: "The Engineer") == "S2, E1 • The Engineer")
    }

    @Test func episodeLineWithoutATitleShowsNumbersOnly() {
        #expect(PlayerEpisodeLabel.text(season: 1, episode: 10, title: nil) == "S1, E10")
        #expect(PlayerEpisodeLabel.text(season: 1, episode: 10, title: "") == "S1, E10")
    }

    // MARK: - Play/Pause

    @Test func pausingShowsTheBarAndKeepsItUp() async throws {
        let (model, engine) = try Self.model(hideDelay: .milliseconds(20))
        model.togglePlayPause()
        #expect(engine.state == .paused)
        #expect(model.bar.isVisible)
        try? await Task.sleep(for: .milliseconds(80))
        #expect(model.bar.isVisible)
    }

    @Test func playbackHidesTheBarAfterTheDelay() async throws {
        let (model, _) = try Self.model(state: .paused, hideDelay: .milliseconds(20))
        model.togglePlayPause()
        #expect(model.bar.isVisible)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(!model.bar.isVisible)
    }

    // MARK: - Skip

    @Test func skipMovesTenSecondsAndShowsTheBar() throws {
        let (model, engine) = try Self.model()
        model.skip(by: PlayerModel.skipInterval)
        model.skip(by: -PlayerModel.skipInterval * 3)
        #expect(engine.seeks == [110, 80])
        #expect(model.bar.isVisible)
    }

    @Test func skipStaysInsideTheTitle() throws {
        let (start, startEngine) = try Self.model(time: 4, duration: 100)
        start.skip(by: -10)
        let (end, endEngine) = try Self.model(time: 95, duration: 100)
        end.skip(by: 10)
        #expect(startEngine.seeks == [0])
        #expect(endEngine.seeks == [100])
    }

    @Test func skipWaitsForADuration() throws {
        let (model, engine) = try Self.model(duration: 0)
        model.skip(by: 10)
        #expect(engine.seeks.isEmpty)
    }

    // MARK: - Scrub

    @Test func swipingWhilePausedScrubsWithoutSeeking() throws {
        let (model, engine) = try Self.model(state: .paused, time: 100, duration: 1000)
        model.scrub(byPadFraction: 0.5)
        #expect(model.scrub?.position(at: .now) == 130)
        #expect(model.displayTime == 130)
        #expect(engine.seeks.isEmpty)
    }

    @Test func repeatedSkipsAddUpBeforeTheEngineCatchesUp() throws {
        let (model, engine) = try Self.model(time: 100)
        engine.seekLands = false
        model.skip(by: 10)
        model.skip(by: 10)
        model.skip(by: 10)
        #expect(engine.seeks == [110, 120, 130])
    }

    @Test func swipingWhilePlayingDoesNothing() throws {
        let (model, _) = try Self.model(state: .playing)
        model.scrub(byPadFraction: 0.5)
        #expect(model.scrub == nil)
    }

    @Test func clickingAfterAScrubPlaysFromThere() throws {
        let (model, engine) = try Self.model(state: .paused, time: 100, duration: 10_000)
        model.scrub(byPadFraction: 0.5)
        model.togglePlayPause()
        #expect(engine.seeks == [130])
        #expect(engine.state == .playing)
        #expect(model.scrub == nil)
    }

    @Test func skipShowsItsGlyphOnItsSide() throws {
        let (model, _) = try Self.model()
        model.skip(by: -10)
        #expect(model.timeIndicator == .skip(.backward))
        #expect(model.timeIndicator?.isLeading == true)
        model.skip(by: 10)
        #expect(model.timeIndicator == .skip(.forward))
        #expect(model.timeIndicator?.isLeading == false)
    }

    @Test func eachSkipGlides() throws {
        let (model, _) = try Self.model()
        model.skip(by: 10)
        model.skip(by: -10)
        #expect(model.skipCount == 2)
    }

    @Test func bufferingAfterASkipBackShowsTheSpinnerBeforeTheTime() throws {
        let (model, engine) = try Self.model()
        model.playbackDidChange()
        model.skip(by: -10)
        engine.state = .buffering
        #expect(model.timeIndicator == .loading(.backward))
        #expect(model.timeIndicator?.isLeading == true)
        #expect(!model.showsLoadingScreen)
    }

    @Test func bufferingWithoutASkipShowsTheSpinnerAfterTheTime() throws {
        let (model, engine) = try Self.model()
        model.playbackDidChange()
        model.noteActivity()
        engine.state = .buffering
        #expect(model.timeIndicator == .loading(.forward))
    }

    @Test func theFirstLoadKeepsTheLoadingScreen() throws {
        let (model, _) = try Self.model(state: .buffering)
        #expect(model.showsLoadingScreen)
        #expect(model.timeIndicator == nil)
    }

    @Test func pausedShowsThePauseGlyph() throws {
        let (model, _) = try Self.model(state: .paused)
        #expect(model.timeIndicator == .paused)
    }

    // MARK: - Menu

    @Test func menuCancelsAScrubAndResumesFromWhereItBegan() throws {
        let (model, engine) = try Self.model(state: .paused, duration: 1000)
        model.scrub(byPadFraction: 0.5)
        #expect(model.handleExit())
        #expect(model.scrub == nil)
        #expect(engine.state == .playing)
        #expect(engine.seeks.isEmpty)
        #expect(!model.bar.isVisible)
        #expect(!model.handleExit())
    }

    @Test func menuHidesTheBarThenExits() throws {
        let (model, _) = try Self.model(state: .paused, duration: 1000)
        model.bar.show(isPlaying: false)
        #expect(model.handleExit())
        #expect(!model.bar.isVisible)
        #expect(!model.handleExit())
    }
}
