import Foundation
import Testing
@testable import HomeTV

/// The hand-off URL Infuse receives, and the matching that turns its `x-success` callback back into
/// episodes.
@MainActor
struct PlaybackQueueTests {

    static func entry(_ episode: Int, url: String) -> PlaybackQueueEntry {
        PlaybackQueueEntry(
            episodeID: "tt0903747:1:\(episode)",
            season: 1,
            episode: episode,
            url: URL(string: url) ?? URL(filePath: "/"),
            filename: "Severance S01E\(episode < 10 ? "0" : "")\(episode).mkv"
        )
    }

    static func queue(_ episodes: [Int]) -> PlaybackQueue {
        PlaybackQueue(
            showID: "tt0903747",
            showName: "Severance",
            entries: episodes.map { entry($0, url: "https://debrid.example/e\($0).mkv") }
        )
    }

    // MARK: - Launch URL

    @Test func theLaunchURLCarriesOneParameterSetPerEpisodeInOrder() throws {
        let url = try #require(PlayerLauncher.infusePlaylistURL(queue: Self.queue([4, 5, 6])))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

        #expect(url.scheme == "infuse")
        #expect(items.filter { $0.name == "url" }.map(\.value) == [
            "https://debrid.example/e4.mkv",
            "https://debrid.example/e5.mkv",
            "https://debrid.example/e6.mkv"
        ])
        #expect(items.filter { $0.name == "filename" }.map(\.value) == [
            "Severance S01E04.mkv", "Severance S01E05.mkv", "Severance S01E06.mkv"
        ])
    }

    @Test func everyItemCarriesEveryKeySoInfuseCanPairThemPositionally() throws {
        let url = try #require(PlayerLauncher.infusePlaylistURL(queue: Self.queue([1, 2, 3])))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let perItem = items.prefix(9).map(\.name)
        #expect(perItem == ["url", "position", "filename", "url", "position", "filename", "url", "position", "filename"])
    }

    @Test func theCallbacksAreDeclaredOnceAtTheEnd() throws {
        let url = try #require(PlayerLauncher.infusePlaylistURL(queue: Self.queue([1, 2])))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.filter { $0.name == "x-success" }.map(\.value) == ["hometv://playback-done"])
        #expect(items.filter { $0.name == "x-error" }.map(\.value) == ["hometv://playback-error"])
    }

    // MARK: - Movie and single-episode names

    @Test func aMovieIsNamedAfterItselfNotItsReleaseFile() throws {
        // Without a filename Infuse shows the release name from the URL
        // (In.the.Grey.2026.2160p.WEB-DL.DDP5.1.Atmos.DV.HDRP-DVT).
        let url = try #require(URL(string: "https://debrid.example/In.the.Grey.2026.2160p.WEB-DL-DVT.mkv"))
        #expect(PlayerFilename.movie(title: "In the Grey", year: 2026, url: url) == "In the Grey (2026).mkv")
        #expect(PlayerFilename.movie(title: "In the Grey", year: nil, url: url) == "In the Grey.mkv")
    }

    @Test func theYearComesFromTheAddonsReleaseInfo() {
        #expect(PlayerFilename.year(fromReleaseInfo: "2026") == 2026)
        #expect(PlayerFilename.year(fromReleaseInfo: "2019–2023") == 2019)
        #expect(PlayerFilename.year(fromReleaseInfo: nil) == nil)
        #expect(PlayerFilename.year(fromReleaseInfo: "unknown") == nil)
    }

    @Test func aSingleLaunchStillCarriesAFilename() throws {
        let queue = Self.queue([4])
        let url = try #require(PlayerLauncher.infuseURL(media: queue.entries[0].url, title: "ignored",
                                                        filename: queue.entries[0].filename))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        // There is no `name` parameter in Infuse's scheme — sending one was why movies showed the
        // release file name.
        #expect(items.map(\.name) == ["url", "filename", "x-success", "x-error"])
        #expect(items.first { $0.name == "filename" }?.value == "Severance S01E04.mkv")
    }

    @Test func theCallbackURLsCarryThePerLaunchToken() throws {
        let url = try #require(PlayerLauncher.infusePlaylistURL(queue: Self.queue([1, 2]), token: "abc123"))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        // In the host, not the query: the player appends its own parameters to this URL.
        #expect(items.first { $0.name == "x-success" }?.value == "hometv://playback-done-abc123")
        #expect(items.first { $0.name == "x-error" }?.value == "hometv://playback-error-abc123")
    }

    @Test func theTokenSurvivesTheParametersThePlayerAppends() throws {
        // The callback URL we hand over carries no query, so the player's first appended parameter is
        // introduced with `?` however naive its string-joining is — and a `?` leaves the host alone.
        let url = try #require(URL(string: "hometv://playback-done-abc123?lastPlayedUrl=x&position=3"))
        let split = PlaybackReturnCoordinator.split(host: url.host)
        #expect(split?.host == "playback-done")
        #expect(split?.token == "abc123")
        // The parameters still parse alongside it.
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.map(\.name) == ["lastPlayedUrl", "position"])
    }

    @Test func aMalformedCallbackFailsClosed() throws {
        // Nothing should produce this — appending `&` to a query-less URL folds the parameters into
        // the host — but if anything did, the token must not match rather than match loosely.
        let url = try #require(URL(string: "hometv://playback-done-abc123&lastPlayedUrl=x"))
        #expect(PlaybackReturnCoordinator.split(host: url.host)?.token != "abc123")
    }

    @Test func aCallbackWithoutATokenNeverMatchesALaunch() {
        #expect(PlaybackReturnCoordinator.split(host: "playback-done")?.token == "")
        #expect(PlaybackReturnCoordinator.split(host: "playback-error")?.token == "")
        #expect(PlaybackReturnCoordinator.split(host: "detail") == nil)
        #expect(PlaybackReturnCoordinator.split(host: nil) == nil)
    }

    @Test func tokensAreUnpredictableAndFullLength() {
        let tokens = (0..<50).map { _ in PlaybackReturnCoordinator.makeToken() }
        #expect(Set(tokens).count == 50)
        #expect(tokens.allSatisfy { $0.count == 32 })
    }

    // MARK: - Reconciling the return

    @Test func theReturnedURLIsFoundInTheQueue() throws {
        let queue = Self.queue([4, 5, 6])
        let returned = URL(string: "https://debrid.example/e5.mkv")
        #expect(queue.index(ofEntryMatching: try #require(returned)) == 1)
    }

    @Test func aReturnedURLMatchesEvenWhenThePlayerReencodedItsQuery() throws {
        // A debrid link can come back with a refreshed token.
        let queue = Self.queue([4, 5, 6])
        let returned = URL(string: "https://debrid.example/e6.mkv?token=refreshed")
        #expect(queue.index(ofEntryMatching: try #require(returned)) == 2)
    }

    @Test func twoEntriesDifferingOnlyByQueryResolveToNeither() throws {
        // Reconciling to the wrong one would mark the wrong episodes watched, so an ambiguous
        // query-less match is no match at all.
        let queue = PlaybackQueue(
            showID: "tt0903747",
            showName: "Severance",
            entries: [Self.entry(1, url: "https://debrid.example/file.mkv?ep=1"),
                      Self.entry(2, url: "https://debrid.example/file.mkv?ep=2")]
        )
        // An exact hit still wins outright.
        #expect(queue.index(ofEntryMatching: try #require(URL(string: "https://debrid.example/file.mkv?ep=2"))) == 1)
        #expect(queue.index(ofEntryMatching: try #require(URL(string: "https://debrid.example/file.mkv?ep=9"))) == nil)
    }

    @Test func pathsThatDifferOnlyByCaseAreDistinct() throws {
        // Host and scheme are case-insensitive; a path on most servers is not.
        let queue = PlaybackQueue(
            showID: "tt0903747",
            showName: "Severance",
            entries: [Self.entry(1, url: "https://debrid.example/Episode.mkv"),
                      Self.entry(2, url: "https://debrid.example/episode.mkv")]
        )
        #expect(queue.index(ofEntryMatching: try #require(URL(string: "https://DEBRID.example/episode.mkv?x=1"))) == 1)
    }

    /// Captured verbatim from an Apple TV: Infuse names the parameter `lastPlayedUrl`, which matched
    /// none of the spellings guessed from its docs. Pinned here so a silent regression is impossible.
    @Test func theRealInfuseCallbackShapeResolvesToAQueueEntry() throws {
        let stream = "https://torrentio.strem.fun/resolve/torbox/73172d74/732137be"
            + "/The.Queens.Gambit.S01E02.2160p.NF.WEB-DL.DDP5.1.HDR.DV.HEVC-SiC.mkv/1"
            + "/The.Queens.Gambit.S01E02.2160p.NF.WEB-DL.DDP5.1.HDR.DV.HEVC-SiC.mkv"
        let queue = PlaybackQueue(
            showID: "tt10048342",
            showName: "The Queen's Gambit",
            entries: [Self.entry(1, url: "https://torrentio.strem.fun/resolve/a/e1.mkv"),
                      Self.entry(2, url: stream)]
        )
        let callback = try #require(URL(string: "hometv://playback-done?lastPlayedUrl=\(stream)&position=38"))
        let items = try #require(URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems)

        #expect(items.map(\.name) == ["lastPlayedUrl", "position"])
        let raw = try #require(items.first { $0.name == PlaybackReturnCoordinator.lastPlayedURLParameter }?.value)
        #expect(queue.index(ofEntryMatching: try #require(URL(string: raw))) == 1)
    }

    @Test func anUnknownReturnedURLMatchesNothing() throws {
        #expect(Self.queue([1, 2]).index(ofEntryMatching: try #require(URL(string: "https://elsewhere.example/x.mkv"))) == nil)
    }
}
