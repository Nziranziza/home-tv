import Foundation
import Testing
@testable import HomeTV

/// Skip segments: decoding both databases, matching chapters, merging and checking the sources.
struct SkipSegmentTests {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    // MARK: - Decoding

    @Test func decodesTheIntroDBWithOpenEndsAndMissingKinds() throws {
        let json = """
        {"tvdb_id":81189,"type":"tv","season":1,"episode":2,
         "intro":[{"start_ms":314549,"end_ms":331133}],
         "credits":[{"start_ms":2848149,"end_ms":null}],
         "recap":[{"start_ms":null,"end_ms":45000}]}
        """
        let source = try Self.decoder().decode(TheIntroDBResponse.self, from: Data(json.utf8)).source
        #expect(source.spans[.intro] == [SkipSegmentSpan(start: 314.549, end: 331.133)])
        #expect(source.spans[.recap] == [SkipSegmentSpan(start: nil, end: 45)])
        #expect(source.spans[.credits] == [SkipSegmentSpan(start: 2848.149, end: nil)])
        #expect(source.postCreditsStart == nil)
    }

    @Test func decodesTheIntroDBMovieWithOnlyCredits() throws {
        let json = #"{"tvdb_id":190,"type":"movie","credits":[{"start_ms":8300000,"end_ms":null}]}"#
        let source = try Self.decoder().decode(TheIntroDBResponse.self, from: Data(json.utf8)).source
        #expect(source.spans.keys.sorted { "\($0)" < "\($1)" } == [.credits])
    }

    @Test func decodesIntroDBAppWithNullsAndPostCredits() throws {
        let json = """
        {"imdb_id":"tt0903747","media_type":"tv","is_movie":false,"season":1,"episode":2,
         "intro":{"start_sec":314.5,"end_sec":331,"start_ms":314500,"end_ms":331000,"confidence":1,
                  "submission_count":5,"updated_at":"2026-08-23T05:11:33.337Z"},
         "recap":null,
         "outro":{"start_ms":2843000,"end_ms":2901000,"confidence":1,"submission_count":1},
         "post_credits":{"start_ms":2880000,"end_ms":2900000,"confidence":0.5,"submission_count":1},
         "no_intro":false,"no_recap":false,"no_outro":false}
        """
        let source = try Self.decoder().decode(IntroDBAppResponse.self, from: Data(json.utf8)).source
        #expect(source.spans[.intro] == [SkipSegmentSpan(start: 314.5, end: 331)])
        #expect(source.spans[.recap] == nil)
        #expect(source.spans[.credits] == [SkipSegmentSpan(start: 2843, end: 2901)])
        #expect(source.postCreditsStart == 2880)
    }

    @Test func decodesAnEmptyIntroDBAppEntry() throws {
        let json = """
        {"imdb_id":"tt9999999","intro":null,"recap":null,"outro":null,"post_credits":null,
         "no_intro":false,"no_recap":false,"no_outro":false}
        """
        let source = try Self.decoder().decode(IntroDBAppResponse.self, from: Data(json.utf8)).source
        #expect(source == SkipSegmentSource())
    }

    @Test func queriesEpisodesByNumberAndMoviesWithoutThem() throws {
        let episode = try #require(SkipSegmentQuery(type: "series", item: PlaybackItem(contentID: "tt0903747:1:2", showID: "tt0903747")))
        #expect(SkipSegmentClient.theIntroDBURL(for: episode)?.absoluteString
            == "https://api.theintrodb.org/v4/media?imdb_id=tt0903747&season=1&episode=2")
        let movie = try #require(SkipSegmentQuery(type: "movie", item: PlaybackItem(contentID: "tt0111161", showID: "tt0111161")))
        #expect(SkipSegmentClient.introDBAppURL(for: movie)?.absoluteString
            == "https://api.introdb.app/segments?imdb_id=tt0111161&is_movie=true")
        #expect(SkipSegmentQuery(type: "series", item: PlaybackItem(contentID: "kitsu:1", showID: "kitsu:1")) == nil)
        #expect(SkipSegmentQuery(type: "movie", item: PlaybackItem(contentID: "tt1", showID: "tt1")) == nil)
        #expect(SkipSegmentQuery(type: "movie", item: PlaybackItem(contentID: "tt１２３４５６７", showID: "tt１２３４５６７")) == nil)
    }

    // MARK: - Chapters

    @Test(arguments: [
        ("Intro", SkipSegment.Kind.intro), ("OPENING", .intro), ("op", .intro), (" Opening Credits ", .intro),
        ("Recap", .recap), ("Previously", .recap),
        ("Credits", .credits), ("End Credits", .credits), ("Ending", .credits), ("ED", .credits), ("Outro", .credits),
    ])
    func matchesChapterTitles(title: String, kind: SkipSegment.Kind) {
        #expect(ChapterSegmentMatcher.kind(ofTitle: title) == kind)
    }

    @Test(arguments: ["Chapter 1", "Opening Scene", "Edit", "", "Introduction"])
    func ignoresOtherChapterTitles(title: String) {
        #expect(ChapterSegmentMatcher.kind(ofTitle: title) == nil)
    }

    @Test func turnsChaptersIntoASource() {
        let chapters = [
            PlaybackChapter(start: 0, end: 90, title: "Chapter 1"),
            PlaybackChapter(start: 90, end: 180, title: "Opening"),
            PlaybackChapter(start: 2500, end: 2600, title: "Ending"),
        ]
        let source = ChapterSegmentMatcher.source(from: chapters)
        #expect(source.spans[.intro] == [SkipSegmentSpan(start: 90, end: 180)])
        #expect(source.spans[.credits] == [SkipSegmentSpan(start: 2500, end: 2600)])
        #expect(source.spans[.recap] == nil)
    }

    // MARK: - Merging and checking

    static func source(_ spans: [SkipSegment.Kind: SkipSegmentSpan], postCredits: TimeInterval? = nil) -> SkipSegmentSource {
        SkipSegmentSource(spans: spans.mapValues { [$0] }, postCreditsStart: postCredits)
    }

    @Test func takesEachKindFromTheFirstSourceThatHasIt() {
        let chapters = Self.source([.intro: SkipSegmentSpan(start: 60, end: 120)])
        let theIntroDB = Self.source([.intro: SkipSegmentSpan(start: 61, end: 121), .credits: SkipSegmentSpan(start: 2500, end: nil)])
        let introDBApp = Self.source([.recap: SkipSegmentSpan(start: 0, end: 40), .credits: SkipSegmentSpan(start: 2400, end: 2600)])
        let segments = SkipSegmentResolver.segments(from: [chapters, theIntroDB, introDBApp], duration: 2600)
        #expect(segments == [
            SkipSegment(kind: .intro, start: 60, end: 120),
            SkipSegment(kind: .recap, start: 0, end: 40),
            SkipSegment(kind: .credits, start: 2500, end: 2600),
        ])
    }

    @Test func fallsBackWhenTheFirstSourcesSegmentIsInvalid() {
        let bad = Self.source([.intro: SkipSegmentSpan(start: 120, end: 60)])
        let good = Self.source([.intro: SkipSegmentSpan(start: 60, end: 120)])
        #expect(SkipSegmentResolver.segments(from: [bad, good], duration: 2600) == [SkipSegment(kind: .intro, start: 60, end: 120)])
    }

    @Test func fillsOpenEndsFromTheFile() {
        #expect(SkipSegmentResolver.validated(SkipSegmentSpan(start: nil, end: 30), duration: 100).map { [$0.start, $0.end] } == [0, 30])
        #expect(SkipSegmentResolver.validated(SkipSegmentSpan(start: 80, end: nil), duration: 100).map { [$0.start, $0.end] } == [80, 100])
    }

    @Test func dropsInvertedShortAndOverlongSegments() {
        #expect(SkipSegmentResolver.validated(SkipSegmentSpan(start: 50, end: 40), duration: 100) == nil)
        #expect(SkipSegmentResolver.validated(SkipSegmentSpan(start: 50, end: 54), duration: 100) == nil)
        #expect(SkipSegmentResolver.validated(SkipSegmentSpan(start: 90, end: 130), duration: 100) == nil)
        #expect(SkipSegmentResolver.validated(SkipSegmentSpan(start: -1, end: 30), duration: 100) == nil)
    }

    @Test func dropsASpanWithNoBounds() {
        #expect(SkipSegmentResolver.validated(SkipSegmentSpan(start: nil, end: nil), duration: 100) == nil)
        let empty = Self.source([.intro: SkipSegmentSpan(start: nil, end: nil)])
        let good = Self.source([.intro: SkipSegmentSpan(start: 60, end: 120)])
        #expect(SkipSegmentResolver.segments(from: [empty, good], duration: 2600) == [SkipSegment(kind: .intro, start: 60, end: 120)])
    }

    @Test func keepsEveryValidSpanFromTheWinningSource() {
        let theIntroDB = SkipSegmentSource(spans: [.recap: [
            SkipSegmentSpan(start: 60, end: 80), SkipSegmentSpan(start: 10, end: 30), SkipSegmentSpan(start: 90, end: 91),
        ]])
        let introDBApp = Self.source([.recap: SkipSegmentSpan(start: 0, end: 40)])
        #expect(SkipSegmentResolver.segments(from: [theIntroDB, introDBApp], duration: 2600) == [
            SkipSegment(kind: .recap, start: 10, end: 30),
            SkipSegment(kind: .recap, start: 60, end: 80),
        ])
    }

    @Test func aSceneRightAfterTheCreditsStartLeavesNoButton() {
        let source = Self.source([.credits: SkipSegmentSpan(start: 2800, end: nil)], postCredits: 2804)
        #expect(SkipSegmentResolver.segments(from: [source], duration: 2950).isEmpty)
    }

    @Test func clampsAnEndJustPastTheFile() {
        #expect(SkipSegmentResolver.validated(SkipSegmentSpan(start: 90, end: 101), duration: 100).map { [$0.start, $0.end] } == [90, 100])
    }

    @Test func creditsSkipToASceneAfterThem() {
        let source = Self.source([.credits: SkipSegmentSpan(start: 2843, end: 2901)], postCredits: 2880)
        let segments = SkipSegmentResolver.segments(from: [source], duration: 2901)
        #expect(segments == [SkipSegment(kind: .credits, start: 2843, end: 2880, scene: 2880)])
    }

    @Test func creditsLandOnAPostCreditsSceneFromAnotherSource() {
        let chapters = Self.source([.credits: SkipSegmentSpan(start: 2800, end: 2900)])
        let introDBApp = SkipSegmentSource(postCreditsStart: 2920)
        let segments = SkipSegmentResolver.segments(from: [chapters, introDBApp], duration: 2950)
        #expect(segments == [SkipSegment(kind: .credits, start: 2800, end: 2900, scene: 2920)])
    }

    @Test func noSegmentsBeforeTheDurationIsKnown() {
        let source = Self.source([.intro: SkipSegmentSpan(start: 60, end: 120)])
        #expect(SkipSegmentResolver.segments(from: [source], duration: 0).isEmpty)
    }

    // MARK: - Active segment

    @Test func activeFromTheStartUntilTwoSecondsBeforeTheEnd() {
        let segments = [SkipSegment(kind: .intro, start: 60, end: 120), SkipSegment(kind: .credits, start: 2500, end: 2600)]
        #expect(SkipSegmentResolver.active(in: segments, at: 59.9) == nil)
        #expect(SkipSegmentResolver.active(in: segments, at: 60)?.kind == .intro)
        #expect(SkipSegmentResolver.active(in: segments, at: 117.9)?.kind == .intro)
        #expect(SkipSegmentResolver.active(in: segments, at: 118) == nil)
        #expect(SkipSegmentResolver.active(in: segments, at: 2550)?.kind == .credits)
    }

    // MARK: - Up Next

    @Test func upNextOpensAtLateCredits() {
        #expect(UpNextTiming.showLead(creditsStart: 2600, duration: 2700) == 100)
    }

    @Test func upNextKeepsItsLeadWithoutUsableCredits() {
        #expect(UpNextTiming.showLead(creditsStart: nil, duration: 2700) == 30)
        #expect(UpNextTiming.showLead(creditsStart: 1500, duration: 2700) == 30)
        #expect(UpNextTiming.showLead(creditsStart: 2700, duration: 2700) == 30)
    }

    @Test func upNextResolvesWithTheSameHeadStartAheadOfCredits() {
        let lead: TimeInterval = 300
        let headStart = UpNextTiming.resolveLead - UpNextTiming.showLead
        #expect(UpNextTiming.isResolveDue(remaining: lead + headStart, showLead: lead))
        #expect(!UpNextTiming.isResolveDue(remaining: lead + headStart + 1, showLead: lead))
    }
}
