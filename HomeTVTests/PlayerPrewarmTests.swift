import Foundation
import Testing
@testable import HomeTV

/// Opening the focused stream before Select, and handing it to the player.
@MainActor
struct PlayerPrewarmTests {
    static let url = URL(filePath: "/streams/Movie.mkv")
    static let otherURL = URL(filePath: "/streams/Other.mkv")

    /// A prewarmer whose models run on fake engines, listed in creation order.
    final class Harness {
        var engines: [FakePlaybackEngine] = []
        lazy var prewarmer = PlayerPrewarmer { [unowned self] request in
            let engine = FakePlaybackEngine()
            engines.append(engine)
            return PlayerModel(request: request, engine: engine, publishesNowPlaying: false, scrobble: { _ in })
        }
    }

    @Test func aPreparedModelPlaysFromTheSameEngine() {
        let engine = FakePlaybackEngine()
        let model = PlayerModel(
            request: PlayerRequest(url: Self.url, startTime: 42),
            engine: engine,
            publishesNowPlaying: false,
            scrobble: { _ in }
        )
        model.prepare()
        #expect(engine.prepares == [Self.url])
        #expect(engine.loads.isEmpty)

        model.start()
        #expect(engine.loads == [Self.url])
        #expect(engine.prepares.count == 1)
    }

    @Test func anUnpreparedModelOnlyLoads() {
        let engine = FakePlaybackEngine()
        let model = PlayerModel(request: PlayerRequest(url: Self.url), engine: engine, publishesNowPlaying: false)
        model.start()
        #expect(engine.prepares.isEmpty)
        #expect(engine.loads == [Self.url])
    }

    @Test func refocusingTheSameStreamKeepsItsBuffer() {
        let harness = Harness()
        harness.prewarmer.prewarm(PlayerRequest(url: Self.url))
        harness.prewarmer.prewarm(PlayerRequest(url: Self.url))
        #expect(harness.engines.count == 1)
    }

    @Test func selectTakesTheMatchingPreparedPlayOnce() throws {
        let harness = Harness()
        harness.prewarmer.prewarm(PlayerRequest(url: Self.url, title: "Dune", startTime: 60))

        // Select builds its own request; only the id differs.
        let selected = PlayerRequest(url: Self.url, title: "Dune", startTime: 60)
        let model = try #require(harness.prewarmer.take(for: selected))
        #expect(model.request.url == Self.url)
        #expect(harness.prewarmer.take(for: selected) == nil)
    }

    @Test func aPreparationThatFailedIsntTaken() throws {
        let harness = Harness()
        harness.prewarmer.prewarm(PlayerRequest(url: Self.url))
        let engine = try #require(harness.engines.first)
        engine.onFinish?(URLError(.badServerResponse))

        #expect(harness.prewarmer.take(for: PlayerRequest(url: Self.url)) == nil)
        #expect(engine.isStopped)
    }

    @Test func aDifferentStartOrStreamIsntTaken() {
        let harness = Harness()
        harness.prewarmer.prewarm(PlayerRequest(url: Self.url, startTime: 60))
        #expect(harness.prewarmer.take(for: PlayerRequest(url: Self.url, startTime: 90)) == nil)

        harness.prewarmer.prewarm(PlayerRequest(url: Self.url))
        #expect(harness.prewarmer.take(for: PlayerRequest(url: Self.otherURL)) == nil)
    }

    @Test func movingOnReplacesThePreparedPlay() {
        let harness = Harness()
        harness.prewarmer.prewarm(PlayerRequest(url: Self.url))
        harness.prewarmer.prewarm(PlayerRequest(url: Self.otherURL))
        #expect(harness.engines.map(\.prepares) == [[Self.url], [Self.otherURL]])
        #expect(harness.engines.map(\.isStopped) == [true, false])

        harness.prewarmer.cancel()
        #expect(harness.engines.map(\.isStopped) == [true, true])
    }
}
