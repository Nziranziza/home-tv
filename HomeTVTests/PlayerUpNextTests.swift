import Foundation
import Testing
@testable import HomeTV

/// The in-app player's Up Next: when it resolves and shows, and what accepting or dismissing it plays.
@MainActor
struct PlayerUpNextTests {
    static let item = PlaybackItem(contentID: "tt1:1:1", showID: "tt1")
    static let stream = SeasonQueueBuilderTests.stream(binge: "pack-4k")

    static func next() throws -> UpNextEpisode {
        let url = try #require(URL(string: "https://debrid.example/S01E02.mkv"))
        let request = PlayerRequest(
            url: url,
            type: "series",
            item: PlaybackItem(contentID: "tt1:1:2", showID: "tt1"),
            continuation: EpisodeContinuation(stream: stream, addonID: "torrentio")
        )
        return UpNextEpisode(request: request, thumbnailURL: nil, label: "S1, E2")
    }

    /// A playing episode `remaining` seconds from its end, whose next episode resolves to `next`.
    static func model(
        remaining: TimeInterval,
        next: UpNextEpisode?,
        failures: Int = 0,
        continuation: EpisodeContinuation? = EpisodeContinuation(stream: stream, addonID: "torrentio")
    ) throws -> (PlayerModel, FakePlaybackEngine, LoadLog) {
        let engine = FakePlaybackEngine()
        engine.duration = 2700
        engine.currentTime = 2700 - remaining
        let url = try #require(URL(string: "https://debrid.example/S01E01.mkv"))
        let log = LoadLog()
        let prewarmer = PlayerPrewarmer { request in
            log.prewarmed.append(request.url)
            return PlayerModel(request: request, engine: FakePlaybackEngine(), publishesNowPlaying: false, scrobble: { _ in })
        }
        let model = PlayerModel(
            request: PlayerRequest(url: url, type: "series", item: item, continuation: continuation),
            engine: engine,
            publishesNowPlaying: false,
            recordProgress: { position, runtime, _ in log.saves.append(position == runtime) },
            scrobble: { _ in },
            loadTitleInfo: { _, _ in nil },
            loadUpNext: { _ in
                log.loads += 1
                if log.loads <= failures { throw URLError(.timedOut) }
                return next
            },
            upNextRetryDelay: .zero,
            prewarmer: prewarmer
        )
        model.start()
        model.playbackDidChange()
        return (model, engine, log)
    }

    @MainActor
    final class LoadLog {
        var loads = 0
        var prewarmed: [URL] = []
        /// One entry per save: true when it saved the end.
        var saves: [Bool] = []
    }

    /// Ticks once, then waits for the lookup it started, then ticks again so the card can show.
    static func tick(_ model: PlayerModel) async {
        model.tickUpNext()
        await model.upNextLoad?.value
        model.tickUpNext()
    }

    @Test func nothingResolvesEarlyInTheEpisode() async throws {
        let (model, _, log) = try Self.model(remaining: 1200, next: Self.next())
        await Self.tick(model)
        #expect(log.loads == 0)
        #expect(!model.isShowingUpNext)
    }

    @Test func resolvesAheadOfUpNextWithoutShowingIt() async throws {
        let (model, _, log) = try Self.model(remaining: 120, next: Self.next())
        await Self.tick(model)
        #expect(log.loads == 1)
        #expect(model.upNext != nil)
        #expect(!model.isShowingUpNext)
        #expect(log.prewarmed.isEmpty)
    }

    @Test func upNextShowsNearTheEndAndOpensTheNextStream() async throws {
        let (model, _, log) = try Self.model(remaining: 20.4, next: Self.next())
        await Self.tick(model)
        #expect(model.isShowingUpNext)
        #expect(model.upNextSecondsLeft == 21)
        #expect(log.prewarmed.map(\.lastPathComponent) == ["S01E02.mkv"])
        model.tickUpNext()
        #expect(log.prewarmed.count == 1)
        #expect(log.loads == 1)
    }

    @Test func playMarksThisEpisodeFinishedAndRollsOver() async throws {
        let (model, _, log) = try Self.model(remaining: 20, next: Self.next())
        await Self.tick(model)
        model.playUpNext()
        #expect(model.didFinish)
        #expect(log.saves == [true])
        #expect(model.nextRequest?.item?.contentID == "tt1:1:2")
    }

    @Test func playingOutAfterTheCardRollsOver() async throws {
        let (model, engine, _) = try Self.model(remaining: 20, next: Self.next())
        await Self.tick(model)
        engine.onFinish?(nil)
        #expect(model.didFinish)
        #expect(model.nextRequest?.item?.contentID == "tt1:1:2")
    }

    @Test func returningToFullScreenStillPlaysTheNextEpisode() async throws {
        let (model, engine, log) = try Self.model(remaining: 20, next: Self.next())
        await Self.tick(model)
        model.dismissUpNext()
        #expect(!model.isShowingUpNext)
        model.tickUpNext()
        #expect(!model.isShowingUpNext)
        engine.onFinish?(nil)
        #expect(model.didFinish)
        #expect(model.nextRequest?.item?.contentID == "tt1:1:2")
        // The opened next stream is kept for the hand-over.
        #expect(log.prewarmed.count == 1)
    }

    @Test func menuReturnsToFullScreen() async throws {
        let (model, _, _) = try Self.model(remaining: 20, next: Self.next())
        await Self.tick(model)
        #expect(model.handleExit())
        #expect(!model.isShowingUpNext)
        #expect(model.nextRequest != nil)
        // A second Menu, with Up Next gone and the bar down, closes the player.
        #expect(!model.handleExit())
    }

    @Test func playPauseDuringUpNextLeavesTheBarDown() async throws {
        let (model, engine, _) = try Self.model(remaining: 20, next: Self.next())
        await Self.tick(model)
        model.togglePlayPause()
        model.playbackDidChange()
        #expect(engine.state == .paused)
        #expect(!model.bar.isVisible)
        model.togglePlayPause()
        #expect(engine.state == .playing)
    }

    @Test func theCountdownRingRunsDownWithTheEpisode() async throws {
        let (model, engine, _) = try Self.model(remaining: 30, next: Self.next())
        await Self.tick(model)
        #expect(model.upNextCountdownFraction == 1)
        engine.currentTime += 15
        model.tickUpNext()
        #expect(model.upNextCountdownFraction == 0.5)
    }

    @Test func aFailedLookupIsTriedAgain() async throws {
        let (model, _, log) = try Self.model(remaining: 20, next: Self.next(), failures: 1)
        await Self.tick(model)
        #expect(log.loads == 1)
        #expect(model.upNext == nil)
        await Self.tick(model)
        #expect(log.loads == 2)
        #expect(model.isShowingUpNext)
    }

    @Test func retriesStopAfterTheLastAttempt() async throws {
        let (model, _, log) = try Self.model(remaining: 20, next: Self.next(), failures: 10)
        for _ in 0..<6 { await Self.tick(model) }
        #expect(log.loads == UpNextTiming.maxAttempts)
        #expect(model.upNext == nil)
    }

    @Test func noNextEpisodeClosesAsBefore() async throws {
        let (model, engine, _) = try Self.model(remaining: 20, next: nil)
        await Self.tick(model)
        #expect(!model.isShowingUpNext)
        engine.onFinish?(nil)
        #expect(model.nextRequest == nil)
    }

    @Test func aPlayWithoutAContinuationNeverLooksUp() async throws {
        let (model, _, log) = try Self.model(remaining: 20, next: Self.next(), continuation: nil)
        await Self.tick(model)
        #expect(log.loads == 0)
    }

    @Test func aResolvedEpisodePlaysEvenIfUpNextNeverShowed() async throws {
        let (model, engine, _) = try Self.model(remaining: 120, next: Self.next())
        await Self.tick(model)
        engine.onFinish?(nil)
        #expect(model.nextRequest?.item?.contentID == "tt1:1:2")
    }

    // MARK: - Next episode

    @Test func theNextEpisodeFollowsInTheSeason() {
        let videos = MetaDetailUpNextTests.episodes(season: 1, 1...3)
        #expect(UpNextLoader.nextEpisode(after: "tt1:1:2", in: videos)?.id == "tt1:1:3")
    }

    @Test func theFinaleContinuesIntoTheNextSeason() {
        let videos = MetaDetailUpNextTests.episodes(season: 2, 1...2) + MetaDetailUpNextTests.episodes(season: 1, 1...3)
        #expect(UpNextLoader.nextEpisode(after: "tt1:1:3", in: videos)?.id == "tt1:2:1")
    }

    @Test func theLastEpisodeHasNoNext() {
        let videos = MetaDetailUpNextTests.episodes(season: 1, 1...3)
        #expect(UpNextLoader.nextEpisode(after: "tt1:1:3", in: videos) == nil)
    }

    @Test func specialsAreSkipped() {
        let videos = MetaDetailUpNextTests.episodes(season: 0, 1...2) + MetaDetailUpNextTests.episodes(season: 1, 1...2)
        #expect(UpNextLoader.nextEpisode(after: "tt1:1:2", in: videos) == nil)
    }

    // MARK: - Continuation

    @Test func aStreamWithoutAReleaseIdentityHasNoContinuation() {
        let stream = SeasonQueueBuilderTests.stream(binge: nil, hash: nil)
        #expect(EpisodeContinuation(stream: stream, addonID: "torrentio") == nil)
        #expect(EpisodeContinuation(stream: Self.stream, addonID: "") == nil)
        #expect(EpisodeContinuation(stream: Self.stream, addonID: "torrentio") != nil)
    }

    @Test func anUppercaseSchemePlaysInApp() throws {
        let stream = SeasonQueueBuilderTests.stream(url: "HTTPS://debrid.example/file.mkv")
        let request = try PlayerRequest(
            stream: stream, type: "series", contentID: "tt1:1:1", title: "Show", logoURL: nil, startTime: 0
        )
        #expect(request.url.absoluteString == "HTTPS://debrid.example/file.mkv")
    }

    @Test func onlyAnEpisodeCarriesItsContinuation() throws {
        let movie = try PlayerRequest(
            stream: Self.stream, type: "movie", contentID: "tt9", title: "Dune", logoURL: nil, startTime: 0,
            continuation: EpisodeContinuation(stream: Self.stream, addonID: "torrentio")
        )
        #expect(movie.continuation == nil)
        let episode = try PlayerRequest(
            stream: Self.stream, type: "series", contentID: "tt1:1:1", title: "Show", logoURL: nil, startTime: 0,
            continuation: EpisodeContinuation(stream: Self.stream, addonID: "torrentio")
        )
        #expect(episode.continuation != nil)
    }
}
