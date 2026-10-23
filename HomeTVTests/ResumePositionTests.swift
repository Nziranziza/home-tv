import Foundation
import Testing
@testable import HomeTV

/// Resume picks up at the saved position in Infuse; anything unstarted, finished or without a runtime
/// starts at 0.
@MainActor
struct ResumePositionTests {

    static let media = URL(string: "https://debrid.example/movie.mkv") ?? URL(filePath: "/")

    static func items(_ url: URL?) throws -> [URLQueryItem] {
        let url = try #require(url)
        return try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    }

    // MARK: - Fraction to seconds

    @Test func aFractionInsideTheResumeRangeBecomesSeconds() {
        #expect(PlayerLauncher.resumePosition(fraction: 0.5, runtimeSeconds: 3600) == 1800)
        #expect(PlayerLauncher.resumePosition(fraction: 0.25, runtimeSeconds: 2700) == 675)
    }

    @Test func anUnknownRuntimeNeverGuesses() {
        #expect(PlayerLauncher.resumePosition(fraction: 0.5, runtimeSeconds: nil) == nil)
        #expect(PlayerLauncher.resumePosition(fraction: 0.5, runtimeSeconds: 0) == nil)
    }

    @Test func unstartedOrFinishedStartsFromTheBeginning() {
        #expect(PlayerLauncher.resumePosition(fraction: nil, runtimeSeconds: 3600) == nil)
        #expect(PlayerLauncher.resumePosition(fraction: 0.005, runtimeSeconds: 3600) == nil)
        #expect(PlayerLauncher.resumePosition(fraction: 0.97, runtimeSeconds: 3600) == nil)
    }

    @Test func savedSecondsWinOverTheFraction() {
        #expect(PlayerLauncher.resumePosition(savedSeconds: 1390, fraction: 0.5, runtimeSeconds: 3600) == 1390)
        // No runtime needed: the metadata lookup can be slow or fail.
        #expect(PlayerLauncher.resumePosition(savedSeconds: 1390, fraction: nil, runtimeSeconds: nil) == 1390)
        #expect(PlayerLauncher.resumePosition(savedSeconds: 0, fraction: 0.5, runtimeSeconds: 3600) == 1800)
    }

    // MARK: - Single launch

    @Test func aSingleLaunchCarriesTheStartPosition() throws {
        let items = try Self.items(PlayerLauncher.infuseURL(media: Self.media, title: "Movie", startPosition: 1800))
        #expect(items.map(\.name) == ["url", "position", "filename", "x-success", "x-error"])
        #expect(items.first { $0.name == "position" }?.value == "1800")
    }

    @Test func aSingleLaunchWithoutAPositionOmitsIt() throws {
        let items = try Self.items(PlayerLauncher.infuseURL(media: Self.media, title: "Movie"))
        #expect(!items.contains { $0.name == "position" })
    }

    // MARK: - Season queue

    @Test func onlyTheSelectedEpisodeResumes() throws {
        let queue = PlaybackQueueTests.queue([4, 5, 6])
        let items = try Self.items(PlayerLauncher.infusePlaylistURL(queue: queue, startPosition: 1234))
        #expect(items.filter { $0.name == "position" }.map(\.value) == ["1234", "0", "0"])
    }

    @Test func aQueueWithoutAPositionStartsEveryEpisodeAtZero() throws {
        let queue = PlaybackQueueTests.queue([4, 5])
        let items = try Self.items(PlayerLauncher.infusePlaylistURL(queue: queue))
        #expect(items.filter { $0.name == "position" }.map(\.value) == ["0", "0"])
    }
}
