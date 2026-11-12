import Foundation
import Testing
@testable import HomeTV

/// The Info tab's badges, genre and runtime line, title info, and panel rules.
@MainActor
struct PlayerInfoTests {

    // MARK: - Badges

    private static func track(_ kind: PlaybackTrack.Kind, sdh: Bool = false, ad: Bool = false) -> PlaybackTrack {
        PlaybackTrack(id: 1, kind: kind, name: "", languageCode: "en", isSelected: false, isSDH: sdh, isAudioDescription: ad)
    }

    @Test func fourKDolbyVisionWithSDHAndAD() {
        let badges = PlayerBadge.badges(
            video: VideoFormat(size: CGSize(width: 3840, height: 2160), dynamicRange: .dolbyVision),
            audio: [Self.track(.audio), Self.track(.audio, ad: true)],
            subtitles: [Self.track(.subtitle, sdh: true)]
        )
        #expect(badges == [.fourK, .dolbyVision, .sdh, .audioDescription])
    }

    @Test func hdNonHDRStreamHasNoVideoBadges() {
        let badges = PlayerBadge.badges(
            video: VideoFormat(size: CGSize(width: 1920, height: 1080), dynamicRange: .sdr),
            audio: [Self.track(.audio)],
            subtitles: [Self.track(.subtitle)]
        )
        #expect(badges.isEmpty)
    }

    @Test func scopeUHDIsFourKAndHDR10() {
        let badges = PlayerBadge.badges(
            video: VideoFormat(size: CGSize(width: 3840, height: 1600), dynamicRange: .hdr10),
            audio: [],
            subtitles: []
        )
        #expect(badges == [.fourK, .hdr10])
    }

    @Test func unknownVideoStillShowsTrackBadges() {
        let badges = PlayerBadge.badges(video: nil, audio: [], subtitles: [Self.track(.subtitle, sdh: true)])
        #expect(badges == [.sdh])
    }

    // MARK: - Genre and runtime

    private static let english = Locale(identifier: "en_US")

    @Test func runtimeReadsHoursAndMinutes() {
        #expect(PlayerInfoLine.runtime(4574, locale: Self.english) == "1 hr 16 min")
        #expect(PlayerInfoLine.runtime(7200, locale: Self.english) == "2 hr")
        #expect(PlayerInfoLine.runtime(2700, locale: Self.english) == "45 min")
        #expect(PlayerInfoLine.runtime(.nan, locale: Self.english) == nil)
    }

    @Test func lineJoinsGenreAndRuntime() {
        #expect(PlayerInfoLine.text(genre: "Special Interest", runtimeSeconds: 4574, locale: Self.english)
            == "Special Interest • 1 hr 16 min")
        #expect(PlayerInfoLine.text(genre: nil, runtimeSeconds: 2700, locale: Self.english) == "45 min")
        #expect(PlayerInfoLine.text(genre: nil, runtimeSeconds: nil) == nil)
    }

    // MARK: - Title info

    private static func meta(
        description: String? = nil,
        poster: String? = nil,
        genres: [String]? = nil,
        runtime: String? = nil,
        videos: [Video]? = nil
    ) -> Meta {
        Meta(
            id: "tt1", type: "series", name: "Severance", poster: poster, background: nil, logo: nil,
            description: description, releaseInfo: nil, runtime: runtime, imdbRating: nil, genres: genres,
            cast: nil, director: nil, videos: videos
        )
    }

    @Test func titleInfoMergesAddOnsInOrder() throws {
        let item = PlaybackItem(contentID: "tt1", showID: "tt1")
        let info = try #require(PlayerTitleInfo.merging(
            [Self.meta(description: "", genres: ["Drama, Thriller"]), Self.meta(description: "Office.", poster: "https://p/1.jpg", runtime: "50 min")],
            type: "movie",
            item: item
        ))
        #expect(info.synopsis == "Office.")
        #expect(info.genre == "Drama")
        #expect(info.runtimeSeconds == 3000)
        #expect(info.posterURL?.absoluteString == "https://p/1.jpg")
        #expect(info.detail.id == "tt1")
        #expect(info.detail.type == "movie")
    }

    @Test func blankPosterFallsThroughToTheNextAddOn() throws {
        let item = PlaybackItem(contentID: "tt1", showID: "tt1")
        let info = try #require(PlayerTitleInfo.merging(
            [Self.meta(poster: " "), Self.meta(poster: "https://p/2.jpg")], type: "movie", item: item
        ))
        #expect(info.posterURL?.absoluteString == "https://p/2.jpg")
        #expect(info.detail.poster == "https://p/2.jpg")
    }

    @Test func episodeSynopsisIsTheEpisodeOverview() throws {
        let item = PlaybackItem(contentID: "tt1:2:1", showID: "tt1")
        let episode = Video(
            id: "tt1:2:1", name: "Hello", title: nil, season: 2, episode: 1, released: nil,
            overview: "Mark returns.", thumbnail: nil
        )
        let info = try #require(PlayerTitleInfo.merging(
            [Self.meta(description: "Office.", videos: [episode])], type: "series", item: item
        ))
        #expect(info.synopsis == "Mark returns.")
        #expect(info.detail.id == "tt1")
    }

    @Test func episodeKeepsLookingPastAShowDescription() {
        let item = PlaybackItem(contentID: "tt1:2:1", showID: "tt1")
        let full = Self.meta(description: "Office.", poster: "https://p/1.jpg", genres: ["Drama"], runtime: "50 min")
        #expect(!PlayerTitleInfo.isComplete([full], type: "series", item: item))
        let episode = Video(
            id: "tt1:2:1", name: "Hello", title: nil, season: 2, episode: 1, released: nil,
            overview: "Mark returns.", thumbnail: nil
        )
        #expect(PlayerTitleInfo.isComplete([full, Self.meta(videos: [episode])], type: "series", item: item))
    }

    @Test func movieIsCompleteWithItsDescription() {
        let item = PlaybackItem(contentID: "tt1", showID: "tt1")
        let full = Self.meta(description: "Office.", poster: "https://p/1.jpg", genres: ["Drama"], runtime: "50 min")
        #expect(PlayerTitleInfo.isComplete([full], type: "movie", item: item))
        #expect(!PlayerTitleInfo.isComplete([Self.meta(description: "Office.")], type: "movie", item: item))
    }

    // MARK: - Panel

    private static func model(item: PlaybackItem? = nil) throws -> (PlayerModel, FakePlaybackEngine) {
        let engine = FakePlaybackEngine()
        engine.state = .playing
        engine.currentTime = 600
        engine.duration = 4574
        let url = try #require(URL(string: "https://debrid.example/Movie.mp4"))
        let model = PlayerModel(
            request: PlayerRequest(url: url, title: "Movie", item: item),
            engine: engine,
            bar: PlayerBarController(),
            publishesNowPlaying: false,
            recordProgress: { _, _, _ in },
            loadTitleInfo: { _, _ in nil }
        )
        return (model, engine)
    }

    @Test func focusOnInfoOrItsButtonsKeepsThePanelUp() throws {
        let (model, _) = try Self.model()
        model.bar.show(isPlaying: true)
        model.focusDidChange(to: .info)
        #expect(model.isInfoOpen)
        model.focusDidChange(to: .goToDetail)
        #expect(model.isInfoOpen)
        model.focusDidChange(to: nil)
        #expect(model.isInfoOpen)
        model.focusDidChange(to: .continueWatching)
        #expect(!model.isInfoOpen)
    }

    @Test func menuClosesThePanelBeforeTheBar() throws {
        let (model, _) = try Self.model()
        model.bar.show(isPlaying: true)
        model.focusDidChange(to: .fromBeginning)
        #expect(model.handleExit())
        #expect(!model.isInfoOpen)
        #expect(model.bar.isVisible)
    }

    @Test func fromBeginningSeeksToZeroPlaysAndHidesTheBar() throws {
        let (model, engine) = try Self.model()
        engine.state = .paused
        model.bar.show(isPlaying: false)
        model.focusDidChange(to: .fromBeginning)
        model.playFromBeginning()
        #expect(engine.seeks == [0])
        #expect(engine.state == .playing)
        #expect(!model.isInfoOpen)
        #expect(!model.bar.isVisible)
        #expect(model.displayTime == 0)
    }

    @Test func goToNeedsALibraryTitle() throws {
        #expect(try Self.model().0.detail == nil)
        let item = PlaybackItem(contentID: "tt1:2:1", showID: "tt1")
        let detail = try #require(try Self.model(item: item).0.detail)
        #expect(detail.id == "tt1")
    }

    @Test func infoLinePrefersTheStreamsLength() throws {
        let (model, _) = try Self.model()
        #expect(model.infoLine?.hasSuffix("16 min") == true)
    }
}
