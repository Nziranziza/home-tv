import Foundation
import Testing
@testable import HomeTV

/// The season hand-off's matching and ordering. `SeasonQueueBuilder` is pure, so these run without a
/// view, a network or an addon.
struct SeasonQueueBuilderTests {

    // MARK: - Fixtures

    static let show = "tt0903747"

    static func video(_ season: Int, _ episode: Int) -> Video {
        Video(
            id: "\(show):\(season):\(episode)",
            name: "Episode \(episode)",
            title: nil,
            season: season,
            episode: episode,
            released: nil,
            overview: nil,
            thumbnail: nil
        )
    }

    static func stream(
        binge: String? = "pack-4k",
        hash: String? = nil,
        url: String? = "https://debrid.example/file.mkv",
        name: String = "[RD+] Torrentio"
    ) -> HomeTV.Stream {
        HomeTV.Stream(
            name: name,
            title: "Show.S01.2160p.WEB-DL-GROUP",
            description: nil,
            url: url,
            ytId: nil,
            infoHash: hash,
            fileIdx: nil,
            sources: nil,
            behaviorHints: binge.map { StreamBehaviorHints(bingeGroup: $0, notWebReady: nil, proxyHeaders: nil) }
        )
    }

    static func candidate(_ stream: HomeTV.Stream, addon: String = "com.torrentio") -> SeasonQueueBuilder.Candidate {
        .init(stream: stream, addonID: addon)
    }

    /// A ten-episode season where every episode is served by the same pack.
    static func fullPack(season: Int = 1, episodes: ClosedRange<Int> = 1...10) -> [String: [SeasonQueueBuilder.Candidate]] {
        var result: [String: [SeasonQueueBuilder.Candidate]] = [:]
        for episode in episodes {
            result["\(show):\(season):\(episode)"] = [candidate(stream(url: "https://debrid.example/e\(episode).mkv"))]
        }
        return result
    }

    static func queue(
        selected: String,
        videos: [Video],
        candidates: [String: [SeasonQueueBuilder.Candidate]],
        selectedStream: HomeTV.Stream? = nil,
        limit: Int = SeasonQueueBuilder.maxEntries
    ) -> PlaybackQueue? {
        SeasonQueueBuilder.queue(
            showID: show,
            showName: "Severance",
            episodes: SeasonQueueBuilder.orderedEpisodes(from: videos),
            selectedEpisodeID: selected,
            selectedStream: selectedStream ?? stream(),
            addonID: "com.torrentio",
            candidates: candidates,
            limit: limit
        )
    }

    static var tenEpisodeSeason: [Video] { (1...10).map { video(1, $0) } }

    // MARK: - Ordering

    @Test func fullPackFromFirstEpisodeQueuesTheWholeSeasonInOrder() {
        let result = Self.queue(selected: "\(Self.show):1:1", videos: Self.tenEpisodeSeason, candidates: Self.fullPack())
        #expect(result?.entries.map(\.episode) == Array(1...10))
    }

    @Test func midSeasonSelectionLeadsAndTheEarlierEpisodesFollowTheFinale() {
        // Infuse has no start index, so the chosen episode has to be first; E01…E03 wrap to the tail.
        let result = Self.queue(selected: "\(Self.show):1:4", videos: Self.tenEpisodeSeason, candidates: Self.fullPack())
        #expect(result?.entries.map(\.episode) == [4, 5, 6, 7, 8, 9, 10, 1, 2, 3])
    }

    @Test func lastEpisodeOfTheSeasonQueuesTheEarlierEpisodesBehindIt() {
        let result = Self.queue(selected: "\(Self.show):1:10", videos: Self.tenEpisodeSeason, candidates: Self.fullPack())
        #expect(result?.entries.first?.episode == 10)
        #expect(result?.entries.count == 10)
    }

    @Test func lastEpisodeWithNothingElseMatchingHasNoQueue() {
        // Scenario 3: behave exactly like today rather than hand over a one-item playlist.
        let result = Self.queue(selected: "\(Self.show):1:10", videos: Self.tenEpisodeSeason, candidates: [:])
        #expect(result == nil)
    }

    // MARK: - Pack shape

    @Test func partialPackStopsWhereTheReleaseStops() {
        // E01–E06 of a ten-episode season: nothing is fabricated for E07…E10.
        let result = Self.queue(selected: "\(Self.show):1:1", videos: Self.tenEpisodeSeason, candidates: Self.fullPack(episodes: 1...6))
        #expect(result?.entries.map(\.episode) == Array(1...6))
    }

    @Test func aGapInThePackStopsTheQueueRatherThanSkippingIt() {
        var candidates = Self.fullPack()
        candidates.removeValue(forKey: "\(Self.show):1:7")
        let result = Self.queue(selected: "\(Self.show):1:4", videos: Self.tenEpisodeSeason, candidates: candidates)
        #expect(result?.entries.map(\.episode) == [4, 5, 6, 1, 2, 3])
    }

    @Test func aCompleteSeriesPackRollsPastTheFinaleIntoTheNextSeason() {
        let videos = (1...3).map { Self.video(1, $0) } + (1...3).map { Self.video(2, $0) }
        var candidates = Self.fullPack(season: 1, episodes: 1...3)
        for (key, value) in Self.fullPack(season: 2, episodes: 1...3) { candidates[key] = value }
        let result = Self.queue(selected: "\(Self.show):1:2", videos: videos, candidates: candidates)
        let codes = result?.entries.map { "S\($0.season)E\($0.episode)" }
        #expect(codes == ["S1E2", "S1E3", "S2E1", "S2E2", "S2E3", "S1E1"])
    }

    @Test func specialsAreNeverQueued() {
        // Season 0 file numbering rarely lines up with a pack's, and a wrong episode is worse than none.
        let videos = [Self.video(0, 1)] + Self.tenEpisodeSeason
        let episodes = SeasonQueueBuilder.orderedEpisodes(from: videos)
        #expect(episodes.allSatisfy { $0.season > 0 })
        #expect(episodes.count == 10)
    }

    @Test func videosWithoutEpisodeNumbersAreDropped() {
        let unnumbered = Video(id: "x", name: nil, title: nil, season: 1, episode: nil, released: nil, overview: nil, thumbnail: nil)
        #expect(SeasonQueueBuilder.orderedEpisodes(from: [unnumbered]).isEmpty)
    }

    // MARK: - Release identity

    @Test func aDifferentBingeGroupIsNotTheSameRelease() {
        var candidates = Self.fullPack()
        candidates["\(Self.show):1:3"] = [Self.candidate(Self.stream(binge: "other-1080p", url: "https://debrid.example/e3.mkv"))]
        let result = Self.queue(selected: "\(Self.show):1:1", videos: Self.tenEpisodeSeason, candidates: candidates)
        #expect(result?.entries.map(\.episode) == [1, 2])
    }

    @Test func anIdenticalInfoHashMatchesWithoutABingeGroup() {
        var candidates: [String: [SeasonQueueBuilder.Candidate]] = [:]
        for episode in 1...3 {
            candidates["\(Self.show):1:\(episode)"] = [
                Self.candidate(Self.stream(binge: nil, hash: "ABCDEF", url: "https://debrid.example/e\(episode).mkv"))
            ]
        }
        let selected = Self.stream(binge: nil, hash: "abcdef")
        let result = Self.queue(
            selected: "\(Self.show):1:1",
            videos: Self.tenEpisodeSeason,
            candidates: candidates,
            selectedStream: selected
        )
        #expect(result?.entries.count == 3)
    }

    @Test func aStreamWithNoIdentityAtAllHasNoQueue() {
        let result = Self.queue(
            selected: "\(Self.show):1:1",
            videos: Self.tenEpisodeSeason,
            candidates: Self.fullPack(),
            selectedStream: Self.stream(binge: nil, hash: nil)
        )
        #expect(result == nil)
    }

    @Test func aStreamFromAnotherAddonIsNotTheSameRelease() {
        var candidates = Self.fullPack()
        candidates["\(Self.show):1:2"] = [
            Self.candidate(Self.stream(url: "https://debrid.example/e2.mkv"), addon: "com.comet")
        ]
        let result = Self.queue(selected: "\(Self.show):1:1", videos: Self.tenEpisodeSeason, candidates: candidates)
        #expect(result == nil)
    }

    // MARK: - HomeTV.Stream realities

    @Test func uncachedDebridEntriesAreExcluded() {
        // A queue that stalls on an [RD download] link three episodes in is worse than a short one.
        var candidates = Self.fullPack()
        candidates["\(Self.show):1:3"] = [
            Self.candidate(Self.stream(url: "https://debrid.example/e3.mkv", name: "[RD download] Torrentio"))
        ]
        let result = Self.queue(selected: "\(Self.show):1:1", videos: Self.tenEpisodeSeason, candidates: candidates)
        #expect(result?.entries.map(\.episode) == [1, 2])
    }

    @Test func magnetOnlyStreamsAreNeverQueued() {
        #expect(SeasonQueueBuilder.isQueueable(Self.stream(hash: "abc", url: nil)) == false)
        let result = Self.queue(
            selected: "\(Self.show):1:1",
            videos: Self.tenEpisodeSeason,
            candidates: Self.fullPack(),
            selectedStream: Self.stream(hash: "abc", url: nil)
        )
        #expect(result == nil)
    }

    @Test func anAddonFailureShortensTheQueueRatherThanBreakingIt() {
        // A failed request simply leaves no candidates for that episode.
        var candidates = Self.fullPack()
        candidates["\(Self.show):1:5"] = []
        let result = Self.queue(selected: "\(Self.show):1:1", videos: Self.tenEpisodeSeason, candidates: candidates)
        #expect(result?.entries.map(\.episode) == Array(1...4))
    }

    // MARK: - Limit

    @Test func theQueueIsCappedSoTheLaunchURLStaysBounded() {
        let videos = (1...40).map { Self.video(1, $0) }
        let result = Self.queue(
            selected: "\(Self.show):1:20",
            videos: videos,
            candidates: Self.fullPack(episodes: 1...40),
            limit: 5
        )
        #expect(result?.entries.map(\.episode) == [20, 21, 22, 23, 24])
    }

    @Test func aCappedMidSeasonQueueFillsForwardBeforeWrappingBackward() {
        let result = Self.queue(
            selected: "\(Self.show):1:9",
            videos: Self.tenEpisodeSeason,
            candidates: Self.fullPack(),
            limit: 4
        )
        #expect(result?.entries.map(\.episode) == [9, 10, 7, 8])
    }

    // MARK: - Naming

    @Test func filenamesUseInfusesRecommendedStyle() throws {
        let url = URL(string: "https://debrid.example/whatever.mkv")
        #expect(PlayerFilename.episode(showName: "Severance", season: 1, episode: 4, url: try #require(url)) == "Severance S01E04.mkv")
    }

    @Test func filenamesPadToTwoDigitsWithoutTruncatingLongerNumbers() throws {
        let url = URL(string: "https://debrid.example/whatever.mp4")
        #expect(PlayerFilename.episode(showName: "One Piece", season: 1, episode: 105, url: try #require(url)) == "One Piece S01E105.mp4")
    }

    @Test func filenamesCarryTheEpisodeTitleForInfusesUnmatchedRows() throws {
        let url = try #require(URL(string: "https://debrid.example/whatever.mkv"))
        let name = PlayerFilename.episode(
            showName: "The Gentlemen", season: 1, episode: 3, episodeTitle: "Gone Fishing", url: url
        )
        #expect(name == "The Gentlemen S01E03 Gone Fishing.mkv")
    }

    @Test func aPlaceholderEpisodeTitleIsNotRepeatedInTheFilename() throws {
        let url = try #require(URL(string: "https://debrid.example/whatever.mkv"))
        for placeholder in ["Episode 3", "E3", "3", "S1E3", "  "] {
            let name = PlayerFilename.episode(
                showName: "Severance", season: 1, episode: 3, episodeTitle: placeholder, url: url
            )
            #expect(name == "Severance S01E03.mkv", "placeholder: \(placeholder)")
        }
    }

    @Test func theEpisodeTitleIsReadFromWhicheverFieldTheAddonUsed() {
        // Cinemeta fills `name` and leaves `title` null; other add-ons do the opposite.
        let cinemeta = Video(id: "a", name: "Lightning Strikes", title: nil, season: 1, episode: 1,
                             released: nil, overview: nil, thumbnail: nil)
        let other = Video(id: "b", name: nil, title: "Lightning Strikes", season: 1, episode: 1,
                          released: nil, overview: nil, thumbnail: nil)
        let blank = Video(id: "c", name: "  ", title: nil, season: 1, episode: 1,
                          released: nil, overview: nil, thumbnail: nil)
        #expect(cinemeta.episodeTitle == "Lightning Strikes")
        #expect(other.episodeTitle == "Lightning Strikes")
        #expect(blank.episodeTitle == nil)
    }

    @Test func theEpisodeTitleComesThroughTheWholeQueue() {
        let videos = [
            Video(id: "\(Self.show):1:1", name: "Refined Aggression", title: nil, season: 1, episode: 1,
                  released: nil, overview: nil, thumbnail: nil),
            Video(id: "\(Self.show):1:2", name: "Tackle Tommy Woo Woo", title: nil, season: 1, episode: 2,
                  released: nil, overview: nil, thumbnail: nil)
        ]
        let result = Self.queue(selected: "\(Self.show):1:1", videos: videos, candidates: Self.fullPack(episodes: 1...2))
        #expect(result?.entries.map(\.filename) == [
            "Severance S01E01 Refined Aggression.mkv",
            "Severance S01E02 Tackle Tommy Woo Woo.mkv"
        ])
    }

    @Test func filenamesDropPathSeparatorsAndUnknownExtensions() throws {
        let url = URL(string: "https://debrid.example/stream?token=abc")
        #expect(PlayerFilename.episode(showName: "9-1-1: Lone Star", season: 2, episode: 3, url: try #require(url)) == "9-1-1 Lone Star S02E03.mkv")
    }

    // MARK: - Runtime

    @Test func runtimeIsParsedFromWhateverShapeTheAddonUses() {
        // Cinemeta writes "58 min"; others use hours, or a bare number of minutes.
        #expect(StreamPickerView.runtimeSeconds(from: "58 min") == 58 * 60)
        #expect(StreamPickerView.runtimeSeconds(from: "1h 2min") == 3600 + 120)
        #expect(StreamPickerView.runtimeSeconds(from: "2h") == 7200)
        #expect(StreamPickerView.runtimeSeconds(from: "45") == 45 * 60)
        #expect(StreamPickerView.runtimeSeconds(from: "unknown") == nil)
        #expect(StreamPickerView.runtimeSeconds(from: nil) == nil)
    }

    // MARK: - Prefetch window

    @Test func prefetchReachesOutwardFromTheSelectionInBothDirections() {
        let episodes = SeasonQueueBuilder.orderedEpisodes(from: Self.tenEpisodeSeason)
        let ids = StreamPickerView.prefetchEpisodeIDs(
            episodes: episodes,
            selectedEpisodeID: "\(Self.show):1:4",
            limit: 4
        )
        // Forward neighbours first, then backward — each ordered outward, because the queue can only
        // grow contiguously from the chosen episode.
        #expect(ids == [
            "\(Self.show):1:5", "\(Self.show):1:6", "\(Self.show):1:7",
            "\(Self.show):1:3", "\(Self.show):1:2", "\(Self.show):1:1"
        ])
    }

    @Test func theForwardWindowIsWhatALaunchWaitsFor() {
        // The queue grows forward first and furthest, so those are the episodes worth waiting on.
        let episodes = SeasonQueueBuilder.orderedEpisodes(from: Self.tenEpisodeSeason)
        let ids = StreamPickerView.prefetchEpisodeIDs(
            episodes: episodes,
            selectedEpisodeID: "\(Self.show):1:8",
            forwardOnly: true
        )
        #expect(ids == ["\(Self.show):1:9", "\(Self.show):1:10"])
    }

    @Test func prefetchSkipsTheSelectedEpisodeItself() {
        let episodes = SeasonQueueBuilder.orderedEpisodes(from: Self.tenEpisodeSeason)
        let ids = StreamPickerView.prefetchEpisodeIDs(episodes: episodes, selectedEpisodeID: "\(Self.show):1:1")
        #expect(!ids.contains("\(Self.show):1:1"))
        #expect(ids.count == 9)
    }

    @Test func anUnknownSelectionPrefetchesNothing() {
        let episodes = SeasonQueueBuilder.orderedEpisodes(from: Self.tenEpisodeSeason)
        #expect(StreamPickerView.prefetchEpisodeIDs(episodes: episodes, selectedEpisodeID: "tt999:9:9").isEmpty)
    }

    @Test func theShowIDIsTheBarePrefixOfAnEpisodeID() {
        #expect(StreamPickerView.showID(fromEpisodeID: "tt0903747:1:4") == "tt0903747")
        #expect(StreamPickerView.showID(fromEpisodeID: "tt0903747") == "tt0903747")
    }
}
