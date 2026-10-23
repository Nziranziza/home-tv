import Foundation
import Testing
@testable import HomeTV

/// When the in-app player saves its position, and what it saves.
@MainActor
struct PlayerProgressTests {

    struct Save: Equatable {
        let position: Int
        let runtime: Int
    }

    static let item = PlaybackItem(contentID: "tt0903747:1:4", showID: "tt0903747")

    /// A model whose saves land in the returned box instead of the library.
    static func model(
        state: PlaybackState = .playing,
        time: TimeInterval = 1390,
        duration: TimeInterval = 2820,
        startTime: TimeInterval = 0,
        item: PlaybackItem? = item
    ) throws -> (PlayerModel, FakePlaybackEngine, SaveLog) {
        let engine = FakePlaybackEngine()
        engine.state = state
        engine.currentTime = time
        engine.duration = duration
        let url = try #require(URL(string: "https://debrid.example/Episode.mkv"))
        let log = SaveLog()
        let model = PlayerModel(
            request: PlayerRequest(url: url, startTime: startTime, item: item),
            engine: engine,
            publishesNowPlaying: false,
            recordProgress: { position, runtime, _ in log.saves.append(Save(position: position, runtime: runtime)) }
        )
        return (model, engine, log)
    }

    @MainActor
    final class SaveLog {
        var saves: [Save] = []
    }

    @Test func savesExactSecondsAndTheFilesRuntime() throws {
        let (model, _, log) = try Self.model(time: 1390.7)
        model.saveProgress()
        #expect(log.saves == [Save(position: 1390, runtime: 2820)])
    }

    @Test func aRepeatOfTheLastSaveIsSkipped() throws {
        let (model, engine, log) = try Self.model()
        model.saveProgress()
        model.saveProgress()
        engine.currentTime = 1400
        model.saveProgress()
        #expect(log.saves.map(\.position) == [1390, 1400])
    }

    @Test func aStreamThatNeverPlayedKeepsItsResumePoint() throws {
        let (model, engine, log) = try Self.model(state: .loading, time: 0)
        model.saveProgress()
        engine.state = .failed
        model.stop()
        #expect(log.saves.isEmpty)
    }

    @Test func aClockStillAtZeroIsNotSaved() throws {
        let (model, _, log) = try Self.model(time: 0, startTime: 1390)
        model.saveProgress()
        #expect(log.saves.isEmpty)
    }

    @Test func aSeekTheEngineHasntFinishedIsSaved() throws {
        let (model, engine, log) = try Self.model()
        engine.seekLands = false
        model.seek(to: 2000)
        model.stop()
        #expect(log.saves.map(\.position) == [2000])
    }

    @Test func aSlowSeekIsSavedAtItsTargetPastTheFirstSecond() async throws {
        let (model, engine, log) = try Self.model()
        engine.seekLands = false
        model.seek(to: 2000)
        // Long enough for the playhead to give up on the seek and show the engine's clock again.
        try? await Task.sleep(for: .milliseconds(1100))
        model.stop()
        #expect(log.saves.map(\.position) == [2000])
    }

    @Test func seekingBackToTheStartIsSaved() throws {
        let (model, _, log) = try Self.model()
        model.seek(to: 0)
        model.stop()
        #expect(log.saves.map(\.position) == [0])
    }

    @Test func pausingSaves() throws {
        let (model, engine, log) = try Self.model()
        model.playbackDidChange()
        engine.state = .paused
        model.playbackDidChange()
        #expect(log.saves.map(\.position) == [1390])
    }

    @Test func closingSaves() throws {
        let (model, _, log) = try Self.model()
        model.stop()
        #expect(log.saves.map(\.position) == [1390])
    }

    @Test func playingToTheEndSavesTheEndOnce() throws {
        let (model, engine, log) = try Self.model(time: 2815)
        model.start()
        engine.onFinish?(nil)
        engine.currentTime = 0
        model.stop()
        #expect(log.saves == [Save(position: 2820, runtime: 2820)])
    }

    @Test func playsWithoutAnItemAreNotSaved() throws {
        let (model, _, log) = try Self.model(item: nil)
        model.stop()
        #expect(log.saves.isEmpty)
    }

    @Test func theBarShowsTheResumePointBeforeTheClockStarts() throws {
        let (model, engine, _) = try Self.model(state: .loading, time: 0, startTime: 1390)
        #expect(model.displayTime == 1390)
        engine.state = .playing
        engine.currentTime = 1391
        model.playbackDidChange()
        #expect(model.displayTime == 1391)
    }
}
