import Foundation
import Testing
@testable import HomeTV

/// The in-app player's routing, presentation timing, add-on headers and default.
@MainActor
struct InAppPlayerTests {

    static func url(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }

    // MARK: - Engine route

    @Test func containersAVPlayerCantOpenGoStraightToFFmpeg() throws {
        #expect(PlaybackRoute.forURL(try Self.url("https://debrid.example/d/abc/Movie.2024.mkv")) == .ffmpeg)
        #expect(PlaybackRoute.forURL(try Self.url("https://debrid.example/Movie.AVI")) == .ffmpeg)
        #expect(PlaybackRoute.forURL(try Self.url("https://debrid.example/clip.webm?token=1")) == .ffmpeg)
    }

    @Test func nativeContainersAndUnknownsStartOnAVPlayer() throws {
        #expect(PlaybackRoute.forURL(try Self.url("https://debrid.example/Movie.mp4")) == .native)
        #expect(PlaybackRoute.forURL(try Self.url("https://cdn.example/master.m3u8")) == .native)
        #expect(PlaybackRoute.forURL(try Self.url("https://debrid.example/resolve/abc")) == .native)
    }

    // MARK: - Presentation

    @Test func playbackFromThePickerPresentsOverIt() throws {
        let presenter = PlayerPresenter()
        presenter.streamPickerDidAppear()
        presenter.present(PlayerRequest(url: try Self.url("https://debrid.example/Movie.mkv")))
        #expect(presenter.pickerRequest != nil)
        #expect(presenter.rootRequest == nil)
        #expect(presenter.isPresenting)

        presenter.pickerRequest = nil
        #expect(!presenter.isPresenting)
    }

    @Test func playbackWithNoPickerPresentsFromTheRoot() throws {
        let presenter = PlayerPresenter()
        presenter.present(PlayerRequest(url: try Self.url("https://debrid.example/Movie.mp4")))
        #expect(presenter.rootRequest != nil)
        #expect(presenter.pickerRequest == nil)
    }

    // MARK: - Failure message

    @Test func onlyAFormatFailureBlamesTheFormat() {
        #expect(PlayerModel.message(for: PlaybackError.unsupportedFormat).contains("format"))
        #expect(PlayerModel.message(for: URLError(.notConnectedToInternet)) == "This stream couldn't be played.")
    }

    // MARK: - Add-on headers

    @Test func proxyHeadersDecodeStremiosRequestShape() throws {
        let json = Data("""
        {"url": "https://host.example/a.mkv",
         "behaviorHints": {"proxyHeaders": {"request": {"User-Agent": "Stremio", "Referer": "https://host.example"}}}}
        """.utf8)
        let stream = try JSONDecoder().decode(Stream.self, from: json)
        #expect(stream.behaviorHints?.proxyHeaders?.request == ["User-Agent": "Stremio", "Referer": "https://host.example"])
    }

    // MARK: - Default player

    @Test func theInAppPlayerIsTheDefault() throws {
        let defaults = try #require(UserDefaults(suiteName: "InAppPlayerTests.default"))
        defaults.removePersistentDomain(forName: "InAppPlayerTests.default")
        #expect(PlayerPreference(defaults: defaults).defaultPlayer == .builtIn)
    }

    @Test func anExplicitChoiceSurvives() throws {
        let defaults = try #require(UserDefaults(suiteName: "InAppPlayerTests.choice"))
        defaults.removePersistentDomain(forName: "InAppPlayerTests.choice")
        PlayerPreference(defaults: defaults).defaultPlayer = .infuse
        #expect(PlayerPreference(defaults: defaults).defaultPlayer == .infuse)
    }
}
