import Foundation
import Testing
@testable import HomeTV

/// Files from subtitle add-ons such as OpenSubtitles: which add-ons are asked, the per-language cap,
/// merging with the stream's files, and files arriving after the opening pick.
@MainActor
struct SubtitleAddonSourceTests {
    static let movie = SubtitleAddonQuery(type: "movie", id: "tt0000002")
    static let episode = SubtitleAddonQuery(type: "series", id: "tt0000001:1:2")

    static func addon(_ manifestJSON: String) throws -> InstalledAddon {
        let manifest = try JSONDecoder().decode(StremioManifest.self, from: Data(manifestJSON.utf8))
        let url = try #require(URL(string: "https://\(manifest.id).example/manifest.json"))
        return InstalledAddon(id: manifest.id, manifestURL: url, manifest: manifest, enabled: true)
    }

    static func file(_ name: String, _ language: String?) -> ExternalSubtitle {
        ExternalSubtitle(url: URL(filePath: "/subs/\(name).srt"), languageCode: language)
    }

    static func subtitle(_ name: String, _ language: String) -> StreamSubtitle {
        StreamSubtitle(id: name, url: "https://subs.example/\(name).srt", lang: language)
    }

    // MARK: - Which add-ons are asked

    @Test func onlyAddonsServingSubtitlesForTheTitleAreAsked() throws {
        let openSubtitles = try Self.addon("""
            {"id": "opensubs", "name": "OpenSubtitles", "resources": ["subtitles"],
             "types": ["movie", "series"], "idPrefixes": ["tt"]}
            """)
        let moviesOnly = try Self.addon("""
            {"id": "movies", "name": "M", "types": ["movie", "series"],
             "resources": [{"name": "subtitles", "types": ["movie"]}]}
            """)
        let kitsuOnly = try Self.addon("""
            {"id": "kitsu", "name": "K", "types": ["series"],
             "resources": [{"name": "subtitles", "types": ["series"], "idPrefixes": ["kitsu:"]}]}
            """)
        let streamsOnly = try Self.addon("""
            {"id": "streams", "name": "S", "resources": ["stream"], "types": ["movie", "series"]}
            """)
        let addons = [openSubtitles, moviesOnly, kitsuOnly, streamsOnly]
        #expect(SubtitleAddonFetcher.sources(for: Self.movie, in: addons) == [openSubtitles.baseURL, moviesOnly.baseURL])
        #expect(SubtitleAddonFetcher.sources(for: Self.episode, in: addons) == [openSubtitles.baseURL])
        let kitsu = SubtitleAddonQuery(type: "series", id: "kitsu:1234:5")
        #expect(SubtitleAddonFetcher.sources(for: kitsu, in: addons) == [kitsuOnly.baseURL])
    }

    @Test func aFullFormResourceUsesOnlyItsOwnListsAndNeedsTypes() throws {
        let ownTypes = try Self.addon("""
            {"id": "own", "name": "O", "types": ["series"], "idPrefixes": ["tt"],
             "resources": [{"name": "subtitles", "types": ["series"]}]}
            """)
        let noTypes = try Self.addon("""
            {"id": "none", "name": "N", "resources": ["subtitles"]}
            """)
        let kitsu = SubtitleAddonQuery(type: "series", id: "kitsu:1234:5")
        #expect(SubtitleAddonFetcher.sources(for: kitsu, in: [ownTypes, noTypes]) == [ownTypes.baseURL])
        #expect(SubtitleAddonFetcher.sources(for: Self.movie, in: [ownTypes, noTypes]).isEmpty)
    }

    @Test func aSavedShortFormStillTakesTheManifestsLists() throws {
        let installed = try Self.addon("""
            {"id": "opensubs", "name": "OpenSubtitles", "resources": ["subtitles"],
             "types": ["movie", "series"], "idPrefixes": ["tt"]}
            """)
        let saved = try JSONDecoder().decode(StremioManifest.self, from: try JSONEncoder().encode(installed.manifest))
        #expect(saved.provides("subtitles", type: "movie", id: "tt0000002"))
        #expect(!saved.provides("subtitles", type: "movie", id: "kitsu:1"))
    }

    @Test func aConfiguredAddonsQueryStaysAQuery() throws {
        let base = try #require(URL(string: "https://subs.example/config/manifest.json?token=abc"))
        #expect(StremioClient.subtitlesURL(baseURL: base, query: Self.movie)?.absoluteString
            == "https://subs.example/config/subtitles/movie/tt0000002.json?token=abc")
    }

    @Test func theRequestCarriesTheEncodedFilename() throws {
        let base = try #require(URL(string: "https://opensubs.example/manifest.json"))
        var query = Self.episode
        #expect(StremioClient.subtitlesURL(baseURL: base, query: query)?.absoluteString
            == "https://opensubs.example/subtitles/series/tt0000001%3A1%3A2.json")
        query.filename = "Show S01E02 [1080p].mkv"
        query.videoSize = 1_234
        #expect(StremioClient.subtitlesURL(baseURL: base, query: query)?.absoluteString
            == "https://opensubs.example/subtitles/series/tt0000001%3A1%3A2/videoSize=1234&filename=Show%20S01E02%20%5B1080p%5D.mkv.json")
    }

    @Test func aMalformedHintDoesNotLoseTheStream() throws {
        let json = #"{"url": "https://a.example/x.mkv", "behaviorHints": {"filename": "x.mkv", "videoSize": "big"}}"#
        let stream = try JSONDecoder().decode(HomeTV.Stream.self, from: Data(json.utf8))
        #expect(stream.behaviorHints?.filename == "x.mkv")
        #expect(stream.behaviorHints?.videoSize == nil)
    }

    // MARK: - Every file, ranked

    @Test func everyFileIsKeptInTheAddonsOrderWithoutRepeats() {
        let files = ExternalSubtitle.list(from: [
            Self.subtitle("en1", "eng"), Self.subtitle("en2", "eng"), Self.subtitle("fr1", "fre"),
            Self.subtitle("en3", "eng"), Self.subtitle("en4", "eng"), Self.subtitle("en1", "eng"),
        ])
        #expect(files.map(\.url.lastPathComponent) == ["en1.srt", "en2.srt", "fr1.srt", "en3.srt", "en4.srt"])
    }

    @Test func addonFilesFollowTheStreamsWithoutRepeats() {
        let attached = [Self.file("a", "en"), Self.file("b", "fr")]
        let arrived = [Self.file("a", "en"), Self.file("c", "en"), Self.file("d", "en"), Self.file("e", "en")]
        let merged = ExternalSubtitle.merged(attached, adding: arrived)
        #expect(merged.map(\.url.lastPathComponent) == ["a.srt", "b.srt", "c.srt", "d.srt", "e.srt"])
    }

    @Test func openSubtitlesReleaseDetailsAreRead() throws {
        let json = """
            {"subtitles": [
              {"id": "1", "url": "https://subs.example/1", "lang": "eng", "fpsMilli": 23976,
               "subtitleFileName": "Show.S01E02.720p.BluRay.x264-REWARD.srt", "releaseGroup": "REWARD",
               "releaseFormat": "BluRay", "movieReleaseName": "Show.S01.720p.BluRay.x264-REWARD"},
              {"id": 2, "url": "https://subs.example/2", "lang": "eng", "fpsMilli": "x",
               "movieReleaseName": "Show - season 1"}
            ]}
            """
        let response = try JSONDecoder().decode(SubtitlesResponse.self, from: Data(json.utf8))
        let files = ExternalSubtitle.list(from: response.subtitles)
        #expect(files.map(\.releaseName) == ["Show.S01E02.720p.BluRay.x264-REWARD", "Show - season 1"])
        #expect(files.first?.releaseGroup == "REWARD")
        #expect(files.first?.frameRate == 23.976)
        #expect(files.last?.frameRate == nil)
    }

    @Test func releaseNamesGiveGroupSourceAndResolution() {
        #expect(SubtitleRelease(name: "Movie.2019.1080p.WEB-DL.DDP5.1.H.264-FLUX.mkv")
            == SubtitleRelease(group: "flux", source: .web, resolution: 1080))
        #expect(SubtitleRelease(name: "Breaking.Bad.S01E02.DSR.XviD-0TV")
            == SubtitleRelease(group: "0tv", source: .tv, resolution: nil))
        #expect(SubtitleRelease(name: "breaking bad 1x02 Eng") == SubtitleRelease())
        #expect(SubtitleRelease(name: "Movie.1080p.WEB-DL.mkv") == SubtitleRelease(source: .web, resolution: 1080))
        #expect(SubtitleRelease(name: "Show.S01E02.720p.BluRay.x264-REWARD.mkv").group == "reward")
    }

    @Test func filesMadeForTheStreamsReleaseComeFirst() {
        let stream = "Breaking.Bad.S01E02.720p.BluRay.x264-REWARD.mkv"
        var wrongRate = Self.file("dvd", "en")
        wrongRate.releaseName = "Breaking.Bad.S01E02.DVDRip.XviD-ORPHEUS"
        wrongRate.frameRate = 25
        var sameRate = Self.file("tv", "en")
        sameRate.releaseName = "Breaking.Bad.S01E02.HDTV.XviD-0TV"
        sameRate.frameRate = 23.976
        var sameSource = Self.file("bluray", "en")
        sameSource.releaseName = "Breaking.Bad.S01E02.1080p.BluRay.x264-OTHER"
        var sameGroup = Self.file("reward", "en")
        sameGroup.releaseName = "Breaking.Bad.S01E02.720p.BluRay.x264-REWARD"
        let files = [wrongRate, sameRate, sameSource, sameGroup]
        let tracks = files.enumerated().map { $1.track(at: $0, isSelected: false) }
        let ranked = SubtitleFileRanking.ranked(tracks, files: files, streamFilename: stream, frameRate: 23.976)
        #expect(ranked.map { ExternalSubtitle.index(of: $0) } == [3, 1, 2, 0])
        // Nothing known about the stream keeps the add-on's order.
        #expect(SubtitleFileRanking.ranked(tracks, files: files, streamFilename: nil, frameRate: nil) == tracks)
    }

    @Test func theMenuGroupsFilesByLanguageBestFirst() throws {
        let engine = FakePlaybackEngine()
        engine.subtitleTracks = [AddonSubtitleTests.english]
        engine.videoFormat = VideoFormat(size: .zero, dynamicRange: .sdr, frameRate: 25)
        var pal = Self.file("pal", "fr")
        pal.releaseName = "Movie.DVDRip-PAL"
        pal.frameRate = 25
        engine.externalSubtitles = [Self.file("fr", "fr"), Self.file("en", "en"), pal]
        let subtitles = Self.subtitles(engine, store: try SubtitleDefaultsTests.store())
        subtitles.tracksDidLoad()
        #expect(subtitles.streamOptions.map(\.name) == ["English"])
        #expect(subtitles.fileLanguages.map(\.name) == ["English", "French"])
        let french = subtitles.files(in: "fr")
        #expect(french.map(\.name) == ["French", "French (2)"])
        #expect(french.map(\.detail) == ["Movie.DVDRip-PAL", nil])
    }

    // MARK: - Late arrival

    static func subtitles(_ engine: FakePlaybackEngine, showID: String? = nil, store: SubtitleChoiceStore) -> PlayerSubtitles {
        SubtitleDefaultsTests.subtitles(engine, showID: showID, store: store)
    }

    static func audio(_ language: String) -> [PlaybackTrack] {
        [PlaybackTrack(id: 1, kind: .audio, name: "", languageCode: language, isSelected: true)]
    }

    @Test func lateFilesJoinTheMenuKeepingTheSelection() throws {
        let engine = FakePlaybackEngine()
        engine.audioTracks = Self.audio("kor")
        engine.subtitleTracks = [AddonSubtitleTests.english]
        let subtitles = Self.subtitles(engine, store: try SubtitleDefaultsTests.store())
        subtitles.tracksDidLoad()
        #expect(subtitles.isOn)
        let selections = engine.subtitleSelections.count

        engine.externalSubtitles = [Self.file("fr", "fr"), Self.file("es", "es")]
        subtitles.filesDidArrive()
        #expect(subtitles.options.map(\.name) == ["English", "French", "Spanish"])
        #expect(subtitles.isOn)
        #expect(subtitles.track == AddonSubtitleTests.english)
        #expect(engine.subtitleSelections.count == selections)
    }

    @Test func lateFilesDoNotTurnSubtitlesOnByThemselves() throws {
        let engine = FakePlaybackEngine()
        engine.audioTracks = Self.audio("kor")
        let subtitles = Self.subtitles(engine, store: try SubtitleDefaultsTests.store())
        subtitles.tracksDidLoad()
        #expect(!subtitles.isOn)
        let selections = engine.subtitleSelections.count

        engine.externalSubtitles = [Self.file("en", "en")]
        subtitles.filesDidArrive()
        #expect(!subtitles.isOn)
        #expect(engine.subtitleSelections.count == selections)
        // On now has a track to show.
        subtitles.turnOn()
        #expect(engine.subtitleSelections.last??.isExternal == true)
    }

    @Test func aDecoderRestartDoesNotLetALateFileTurnSubtitlesOn() throws {
        let engine = FakePlaybackEngine()
        engine.audioTracks = Self.audio("kor")
        let subtitles = Self.subtitles(engine, store: try SubtitleDefaultsTests.store())
        subtitles.tracksDidLoad()
        engine.externalSubtitles = [Self.file("en", "en")]
        subtitles.filesDidArrive()
        subtitles.tracksDidLoad()
        #expect(!subtitles.isOn)
        #expect(engine.subtitleSelections.last == .some(nil))
        #expect(subtitles.track?.isExternal == true)
    }

    @Test func filesBeforeTheOpeningPickTakePartInIt() throws {
        let engine = FakePlaybackEngine()
        engine.audioTracks = Self.audio("kor")
        let subtitles = Self.subtitles(engine, store: try SubtitleDefaultsTests.store())
        engine.externalSubtitles = [Self.file("en", "en")]
        subtitles.filesDidArrive()
        #expect(engine.subtitleSelections.isEmpty)
        subtitles.tracksDidLoad()
        #expect(subtitles.isOn)
        #expect(engine.subtitleSelections.last??.isExternal == true)
    }

    @Test func aRememberedLanguageOnlyAnAddonHasIsSelectedOnArrival() throws {
        let store = try SubtitleDefaultsTests.store()
        store.record(SubtitleChoice(isOn: true, languageCode: "fr"), forShow: "tt0000001")
        let engine = FakePlaybackEngine()
        engine.audioTracks = Self.audio("eng")
        engine.subtitleTracks = [AddonSubtitleTests.english]
        let subtitles = Self.subtitles(engine, showID: "tt0000001", store: store)
        subtitles.tracksDidLoad()

        engine.externalSubtitles = [Self.file("fr", "fr")]
        subtitles.filesDidArrive()
        #expect(subtitles.isOn)
        #expect(subtitles.trackName == "French")
        #expect(engine.subtitleSelections.last??.isExternal == true)
    }

    @Test func aChoiceMadeThisPlayIsNotOverridden() throws {
        let store = try SubtitleDefaultsTests.store()
        store.record(SubtitleChoice(isOn: true, languageCode: "fr"), forShow: "tt0000001")
        let engine = FakePlaybackEngine()
        engine.audioTracks = Self.audio("eng")
        engine.subtitleTracks = [AddonSubtitleTests.english]
        let subtitles = Self.subtitles(engine, showID: "tt0000001", store: store)
        subtitles.tracksDidLoad()
        subtitles.turnOff()

        engine.externalSubtitles = [Self.file("fr", "fr")]
        subtitles.filesDidArrive()
        #expect(!subtitles.isOn)
        #expect(engine.subtitleSelections.last == .some(nil))
    }

    @Test func aRememberedAddonFileWinsOverTheStreamsTrackInItsLanguage() throws {
        let store = try SubtitleDefaultsTests.store()
        let engine = FakePlaybackEngine()
        engine.audioTracks = Self.audio("kor")
        engine.subtitleTracks = [AddonSubtitleTests.english]
        let first = Self.subtitles(engine, showID: "tt0000001", store: store)
        first.tracksDidLoad()
        #expect(first.track == AddonSubtitleTests.english)

        // Picked in S1E1 over the stream's English; S1E2 opens on the stream's until the file arrives.
        engine.externalSubtitles = [Self.file("en", "en")]
        first.filesDidArrive()
        let addonEnglish = try #require(first.options.last)
        first.select(addonEnglish)

        let next = FakePlaybackEngine()
        next.audioTracks = Self.audio("kor")
        next.subtitleTracks = [AddonSubtitleTests.english]
        let second = Self.subtitles(next, showID: "tt0000001", store: store)
        second.tracksDidLoad()
        #expect(second.track == AddonSubtitleTests.english)
        next.externalSubtitles = [Self.file("en2", "en")]
        second.filesDidArrive()
        #expect(second.track?.isExternal == true)
        #expect(next.subtitleSelections.last??.isExternal == true)
    }

    @Test func aRememberedStreamTrackStaysWhenAddonFilesInItsLanguageArrive() throws {
        let store = try SubtitleDefaultsTests.store()
        store.record(SubtitleChoice(isOn: true, languageCode: "eng", isExternal: false), forShow: "tt0000001")
        let engine = FakePlaybackEngine()
        engine.audioTracks = Self.audio("eng")
        engine.subtitleTracks = [AddonSubtitleTests.english]
        let subtitles = Self.subtitles(engine, showID: "tt0000001", store: store)
        subtitles.tracksDidLoad()
        let selections = engine.subtitleSelections.count

        engine.externalSubtitles = [Self.file("en", "en")]
        subtitles.filesDidArrive()
        #expect(subtitles.track == AddonSubtitleTests.english)
        #expect(engine.subtitleSelections.count == selections)
    }

    // MARK: - Player

    @Test func thePlayerStartsWithoutWaitingAndAddsFilesAfterTheStreams() async throws {
        let engine = FakePlaybackEngine()
        let (batches, continuation) = AsyncStream.makeStream(of: [ExternalSubtitle].self)
        var queries: [SubtitleAddonQuery] = []
        let url = try #require(URL(string: "https://debrid.example/movie.mkv"))
        let model = PlayerModel(
            request: PlayerRequest(
                url: url,
                item: PlaybackItem(contentID: "tt0000002", showID: "tt0000002"),
                subtitles: [Self.file("attached", "en")],
                subtitleQuery: Self.movie
            ),
            engine: engine,
            publishesNowPlaying: false,
            recordProgress: { _, _, _ in },
            scrobble: { _ in },
            subtitleChoices: try SubtitleDefaultsTests.store(),
            loadTitleInfo: { _, _ in nil },
            skipsSegments: false,
            loadSkipSegments: { _ in [] },
            fetchAddonSubtitles: { query in
                queries.append(query)
                return batches
            }
        )
        model.prepare()
        model.start()
        #expect(engine.loads == [url])
        #expect(queries == [Self.movie])

        continuation.yield([Self.file("attached", "en"), Self.file("fr", "fr")])
        continuation.finish()
        await model.addonSubtitleLoad?.value
        #expect(engine.externalSubtitles.map(\.url.lastPathComponent) == ["attached.srt", "fr.srt"])
        model.stop()
    }

    @Test func menuBacksOutOfALanguagesFilesToLanguage() throws {
        let url = try #require(URL(string: "https://debrid.example/movie.mkv"))
        let model = PlayerModel(
            request: PlayerRequest(url: url),
            engine: FakePlaybackEngine(),
            publishesNowPlaying: false,
            recordProgress: { _, _, _ in },
            scrobble: { _ in },
            loadTitleInfo: { _, _ in nil },
            skipsSegments: false,
            loadSkipSegments: { _ in [] }
        )
        model.openSubtitlesMenu()
        model.showSubtitlesMenu(.files(languageCode: "fr", name: "French"))
        #expect(model.handleExit())
        #expect(model.subtitlesMenu == .language)
        #expect(model.handleExit())
        #expect(model.subtitlesMenu == .root)
    }
}
