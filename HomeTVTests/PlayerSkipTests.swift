import Foundation
import Testing
@testable import HomeTV

/// The in-app player's Skip button: when it shows, what Skip and Menu do, and Up Next at the credits.
@MainActor
struct PlayerSkipTests {
    static let intro = SkipSegmentSpan(start: 60, end: 120)

    /// A playing title at `time` of 2700s, whose databases report `sources`.
    static func model(
        at time: TimeInterval,
        type: String = "series",
        sources: [SkipSegmentSource],
        chapters: [PlaybackChapter] = [],
        isEnabled: Bool = true,
        continuation: EpisodeContinuation? = nil,
        next: UpNextEpisode? = nil
    ) async throws -> (PlayerModel, FakePlaybackEngine) {
        let engine = FakePlaybackEngine()
        engine.duration = 2700
        engine.currentTime = time
        engine.chapters = chapters
        let url = try #require(URL(string: "https://debrid.example/S01E01.mkv"))
        let item = type == "movie"
            ? PlaybackItem(contentID: "tt0000002", showID: "tt0000002")
            : PlaybackItem(contentID: "tt0000001:1:1", showID: "tt0000001")
        let model = PlayerModel(
            request: PlayerRequest(url: url, type: type, item: item, continuation: continuation),
            engine: engine,
            publishesNowPlaying: false,
            recordProgress: { _, _, _ in },
            scrobble: { _ in },
            loadTitleInfo: { _, _ in nil },
            loadUpNext: { _ in next },
            upNextRetryDelay: .zero,
            prewarmer: PlayerPrewarmer { PlayerModel(request: $0, engine: FakePlaybackEngine(), publishesNowPlaying: false, scrobble: { _ in }) },
            skipsSegments: isEnabled,
            loadSkipSegments: { _ in sources }
        )
        model.start()
        model.playbackDidChange()
        await model.skips.loadTask?.value
        model.tickSkip()
        return (model, engine)
    }

    static func source(_ spans: [SkipSegment.Kind: SkipSegmentSpan], postCredits: TimeInterval? = nil) -> SkipSegmentSource {
        SkipSegmentTests.source(spans, postCredits: postCredits)
    }

    @Test func showsSkipIntroDuringTheIntro() async throws {
        let (model, _) = try await Self.model(at: 70, sources: [Self.source([.intro: Self.intro])])
        #expect(model.skipSegment?.kind == .intro)
        #expect(model.skipSegment?.kind.title == "Skip Intro")
    }

    @Test func hidesOutsideTheSegmentAndNearItsEnd() async throws {
        let (model, engine) = try await Self.model(at: 30, sources: [Self.source([.intro: Self.intro])])
        #expect(model.skipSegment == nil)
        engine.currentTime = 119
        model.tickSkip()
        #expect(model.skipSegment == nil)
    }

    @Test func skipSeeksToTheSegmentsEnd() async throws {
        let (model, engine) = try await Self.model(at: 70, sources: [Self.source([.intro: Self.intro])])
        model.skipCurrentSegment()
        #expect(engine.accurateSeeks == [120])
        #expect(model.skipSegment == nil)
    }

    @Test func staysHiddenWhenTheSkipLandsJustInsideTheSegment() async throws {
        let (model, engine) = try await Self.model(at: 70, sources: [Self.source([.intro: Self.intro])])
        engine.seekLands = false
        model.skipCurrentSegment()
        // The engine landed on a keyframe before the end.
        engine.currentTime = 112
        model.tickSkip()
        #expect(model.skipSegment == nil)
    }

    @Test func menuDismissesTheButtonUntilPlaybackLeavesTheSegment() async throws {
        let (model, engine) = try await Self.model(at: 70, sources: [Self.source([.intro: Self.intro])])
        #expect(model.handleExit())
        #expect(model.skipSegment == nil)
        engine.currentTime = 80
        model.tickSkip()
        #expect(model.skipSegment == nil)
        // Back before the intro and into it again.
        engine.currentTime = 30
        model.tickSkip()
        engine.currentTime = 70
        model.tickSkip()
        #expect(model.skipSegment?.kind == .intro)
    }

    @Test func menuClosesThePlayerOnceTheButtonIsGone() async throws {
        let (model, _) = try await Self.model(at: 30, sources: [Self.source([.intro: Self.intro])])
        #expect(!model.handleExit())
    }

    @Test func hiddenWhileScanning() async throws {
        let (model, _) = try await Self.model(at: 70, sources: [Self.source([.intro: Self.intro])])
        model.beginScan(.forward)
        #expect(model.skipSegment == nil)
    }

    @Test func hiddenWhileAMenuIsOpen() async throws {
        let (model, _) = try await Self.model(at: 70, sources: [Self.source([.intro: Self.intro])])
        model.openAudioMenu()
        #expect(model.skipSegment == nil)
    }

    @Test func offInSettingsShowsNothing() async throws {
        let (model, _) = try await Self.model(at: 70, sources: [Self.source([.intro: Self.intro])], isEnabled: false)
        #expect(model.skipSegment == nil)
    }

    @Test func chaptersComeBeforeTheDatabases() async throws {
        let chapters = [PlaybackChapter(start: 10, end: 40, title: "Recap"), PlaybackChapter(start: 200, end: 260, title: "Intro")]
        let (model, engine) = try await Self.model(at: 70, sources: [Self.source([.intro: Self.intro])], chapters: chapters)
        engine.onTracksReady?()
        await model.chapterLoad?.value
        model.tickSkip()
        #expect(model.skipSegment == nil)
        engine.currentTime = 210
        model.tickSkip()
        #expect(model.skipSegment == SkipSegment(kind: .intro, start: 200, end: 260))
    }

    @Test func movieCreditsSkipToAPostCreditsScene() async throws {
        let source = Self.source([.credits: SkipSegmentSpan(start: 2500, end: nil)], postCredits: 2650)
        let (model, engine) = try await Self.model(at: 2510, type: "movie", sources: [source])
        #expect(model.skipSegment?.kind == .credits)
        model.skipCurrentSegment()
        #expect(engine.seeks == [2650])
        #expect(!model.didFinish)
    }

    @Test func aSceneInTheFilesLastSecondIsStillSeekedTo() async throws {
        let source = Self.source([.credits: SkipSegmentSpan(start: 2500, end: nil)], postCredits: 2699.5)
        let (model, engine) = try await Self.model(at: 2510, type: "movie", sources: [source])
        model.skipCurrentSegment()
        #expect(engine.accurateSeeks == [2699.5])
        #expect(!model.didFinish)
    }

    @Test func hiddenWhenPlaybackFailed() async throws {
        let (model, engine) = try await Self.model(at: 70, sources: [Self.source([.intro: Self.intro])])
        engine.state = .failed
        #expect(model.skipSegment == nil)
    }

    @Test func skipOnlyRefreshesWhenChaptersChangedTheSegment() async throws {
        let chapters = [PlaybackChapter(start: 60, end: 90, title: "Intro")]
        let (model, engine) = try await Self.model(at: 70, sources: [Self.source([.intro: Self.intro])], chapters: chapters)
        #expect(model.skipSegment?.end == 120)
        // The chapters land between ticks.
        model.skips.chaptersDidLoad(chapters)
        model.skipCurrentSegment()
        #expect(engine.seeks.isEmpty)
        #expect(model.skipSegment?.end == 90)
    }

    @Test func creditsToTheEndFinishPlayback() async throws {
        let source = Self.source([.credits: SkipSegmentSpan(start: 2500, end: nil)])
        let (model, engine) = try await Self.model(at: 2510, type: "movie", sources: [source])
        model.skipCurrentSegment()
        #expect(engine.seeks.isEmpty)
        #expect(model.didFinish)
    }

    @Test func upNextOpensWhenTheCreditsStart() async throws {
        let source = Self.source([.credits: SkipSegmentSpan(start: 2600, end: nil)])
        let continuation = EpisodeContinuation(stream: PlayerUpNextTests.stream, addonID: "torrentio")
        let (model, _) = try await Self.model(
            at: 2610, sources: [source], continuation: continuation, next: try PlayerUpNextTests.next()
        )
        await PlayerUpNextTests.tick(model)
        #expect(model.isShowingUpNext)
        // Up Next stands in for Skip Credits.
        #expect(model.skipSegment == nil)
    }

    @Test func upNextWaitsForItsUsualLeadWithoutCredits() async throws {
        let continuation = EpisodeContinuation(stream: PlayerUpNextTests.stream, addonID: "torrentio")
        let (model, _) = try await Self.model(
            at: 2610, sources: [], continuation: continuation, next: try PlayerUpNextTests.next()
        )
        await PlayerUpNextTests.tick(model)
        #expect(!model.isShowingUpNext)
    }

    @Test func noSkipCreditsWhileTheNextEpisodeIsStillResolving() async throws {
        let source = Self.source([.credits: SkipSegmentSpan(start: 2600, end: nil)])
        let continuation = EpisodeContinuation(stream: PlayerUpNextTests.stream, addonID: "torrentio")
        let (model, _) = try await Self.model(at: 2610, sources: [source], continuation: continuation, next: nil)
        // Resumed into the credits, before the lookup answers.
        #expect(model.skipSegment == nil)
        await PlayerUpNextTests.tick(model)
        #expect(model.skipSegment?.kind == .credits)
    }

    @Test func upNextStaysOpenWhenLaterCreditsArrive() async throws {
        let source = Self.source([.credits: SkipSegmentSpan(start: 2600, end: nil)])
        let continuation = EpisodeContinuation(stream: PlayerUpNextTests.stream, addonID: "torrentio")
        let (model, engine) = try await Self.model(
            at: 2610, sources: [source], continuation: continuation, next: try PlayerUpNextTests.next()
        )
        await PlayerUpNextTests.tick(model)
        #expect(model.isShowingUpNext)
        model.skips.chaptersDidLoad([PlaybackChapter(start: 2670, end: 2700, title: "Credits")])
        engine.currentTime = 2611
        model.tickUpNext()
        #expect(model.isShowingUpNext)
    }

    @Test func earlyLookupFailuresGetAnotherRoundAtTheUsualPoint() async throws {
        let source = Self.source([.credits: SkipSegmentSpan(start: 2100, end: nil)])
        let engine = FakePlaybackEngine()
        engine.duration = 2700
        engine.currentTime = 2700 - 870
        let url = try #require(URL(string: "https://debrid.example/S01E01.mkv"))
        let next = try PlayerUpNextTests.next()
        var loads = 0
        let model = PlayerModel(
            request: PlayerRequest(
                url: url,
                type: "series",
                item: PlaybackItem(contentID: "tt0000001:1:1", showID: "tt0000001"),
                continuation: EpisodeContinuation(stream: PlayerUpNextTests.stream, addonID: "torrentio")
            ),
            engine: engine,
            publishesNowPlaying: false,
            recordProgress: { _, _, _ in },
            scrobble: { _ in },
            loadTitleInfo: { _, _ in nil },
            loadUpNext: { _ in
                loads += 1
                if loads <= UpNextTiming.maxAttempts { throw URLError(.timedOut) }
                return next
            },
            upNextRetryDelay: .zero,
            prewarmer: PlayerPrewarmer { PlayerModel(request: $0, engine: FakePlaybackEngine(), publishesNowPlaying: false, scrobble: { _ in }) },
            skipsSegments: true,
            loadSkipSegments: { _ in [source] }
        )
        model.start()
        model.playbackDidChange()
        await model.skips.loadTask?.value
        // Credits 600s before the end start the lookup 870s out; every early attempt fails.
        for _ in 0..<UpNextTiming.maxAttempts { await PlayerUpNextTests.tick(model) }
        #expect(loads == UpNextTiming.maxAttempts)
        #expect(!model.isUpNextSettled)
        // At the usual five minutes, one more round finds it.
        engine.currentTime = 2700 - UpNextTiming.resolveLead
        await PlayerUpNextTests.tick(model)
        #expect(model.upNext != nil)
    }

    @Test func lastEpisodeOffersSkipCredits() async throws {
        let source = Self.source([.credits: SkipSegmentSpan(start: 2600, end: nil)])
        let continuation = EpisodeContinuation(stream: PlayerUpNextTests.stream, addonID: "torrentio")
        let (model, _) = try await Self.model(at: 2610, sources: [source], continuation: continuation, next: nil)
        await PlayerUpNextTests.tick(model)
        #expect(!model.isShowingUpNext)
        #expect(model.skipSegment?.kind == .credits)
    }
}
