import Foundation
import Testing
@testable import HomeTV

/// Add-on subtitle files in the Language menu, and subtitle timing.
@MainActor
struct AddonSubtitleTests {
    static let english = SubtitleDefaultsTests.track(1, "eng")
    static let korean = SubtitleDefaultsTests.track(2, "kor")

    static func file(_ index: Int, _ language: String?) -> PlaybackTrack {
        ExternalSubtitle(url: url(index), languageCode: SubtitleLanguage.normalized(language))
            .track(at: index, isSelected: false)
    }

    static func url(_ index: Int) -> URL {
        URL(filePath: "/subs/\(index).srt")
    }

    static func names(_ tracks: [PlaybackTrack]) -> [String] {
        SubtitleTrackName.names(for: tracks, locale: Locale(identifier: "en_US"))
    }

    // MARK: - Files from the add-on

    @Test func filesKeepOnlyTheirLanguageAndDropRepeats() {
        let subtitles = ExternalSubtitle.list(from: [
            StreamSubtitle(id: "OpenSubtitles 1", url: "https://subs.example/a.srt", lang: "eng"),
            StreamSubtitle(id: "OpenSubtitles 2", url: "https://subs.example/a.srt", lang: "eng"),
            StreamSubtitle(id: "x", url: "https://subs.example/b.srt", lang: "pob"),
            StreamSubtitle(id: "y", url: nil, lang: "fre"),
        ])
        #expect(subtitles.map(\.languageCode) == ["en", "pt-BR"])
    }

    @Test func trackIDsRoundTrip() {
        let track = Self.file(3, "eng")
        #expect(track.isExternal)
        #expect(track.id < 0)
        #expect(ExternalSubtitle.index(of: track) == 3)
        #expect(ExternalSubtitle.index(of: Self.english) == nil)
    }

    // MARK: - Menu order and names

    @Test func threeFilesAreNamedByLanguage() {
        let files = [Self.file(0, "eng"), Self.file(1, "fre"), Self.file(2, "spa")]
        let list = SubtitleTrackList.tracks(embedded: [], external: files, deviceLanguage: "en-US")
        #expect(Self.names(list) == ["English", "French", "Spanish"])
    }

    @Test func filesInALanguageTheStreamHasAreDropped() {
        let files = [Self.file(0, "eng"), Self.file(1, "fre")]
        let list = SubtitleTrackList.tracks(embedded: [Self.english], external: files, deviceLanguage: "en-US")
        #expect(list == [Self.english, files[1]])
    }

    @Test func aDifferentScriptIsNotADuplicate() {
        let embedded = SubtitleDefaultsTests.track(5, "zh-Hans")
        let file = Self.file(0, "zh-Hant")
        let list = SubtitleTrackList.tracks(embedded: [embedded], external: [file], deviceLanguage: "en-US")
        #expect(list == [embedded, file])
    }

    @Test func embeddedFirstThenTheDeviceLanguage() {
        let files = [Self.file(0, "fre"), Self.file(1, "eng")]
        let list = SubtitleTrackList.tracks(embedded: [Self.korean, Self.english], external: files, deviceLanguage: "fr-FR")
        #expect(list == [Self.korean, Self.english, files[0]])
        let onEnglish = SubtitleTrackList.tracks(embedded: [Self.korean], external: files, deviceLanguage: "en-US")
        #expect(onEnglish == [Self.korean, files[1], files[0]])
    }

    @Test func repeatedLanguagesAreNumberedAndKeptTogether() {
        let files = [Self.file(0, "eng"), Self.file(1, "fre"), Self.file(2, "eng"), Self.file(3, "eng")]
        let list = SubtitleTrackList.tracks(embedded: [], external: files, deviceLanguage: "en-US")
        #expect(Self.names(list) == ["English", "English (2)", "English (3)", "French"])
    }

    // MARK: - Selection

    static func subtitles(
        _ engine: FakePlaybackEngine,
        delayKey: String? = nil,
        delays: SubtitleDelayStore? = nil
    ) throws -> PlayerSubtitles {
        PlayerSubtitles(
            engine: engine,
            showID: nil,
            store: try SubtitleDefaultsTests.store(),
            delayKey: delayKey,
            delays: try delays ?? Self.delayStore(),
            deviceLanguage: "en-US"
        )
    }

    static func delayStore(suite: String = "AddonSubtitleTests.\(UUID().uuidString)") throws -> SubtitleDelayStore {
        SubtitleDelayStore(defaults: try #require(UserDefaults(suiteName: suite)))
    }

    @Test func koreanAudioOpensWithTheAddonsEnglishFile() throws {
        let engine = FakePlaybackEngine()
        engine.audioTracks = [PlaybackTrack(id: 1, kind: .audio, name: "", languageCode: "kor", isSelected: true)]
        engine.subtitleTracks = [Self.korean]
        engine.externalSubtitles = [ExternalSubtitle(url: Self.url(0), languageCode: "en")]
        let subtitles = try Self.subtitles(engine)
        subtitles.tracksDidLoad()
        #expect(subtitles.isOn)
        #expect(engine.subtitleSelections.last??.isExternal == true)
        #expect(subtitles.trackName == "English")
    }

    @Test func choosingAFileSelectsIt() throws {
        let engine = FakePlaybackEngine()
        engine.subtitleTracks = [Self.english]
        engine.externalSubtitles = [ExternalSubtitle(url: Self.url(0), languageCode: "fr")]
        let subtitles = try Self.subtitles(engine)
        subtitles.tracksDidLoad()
        let french = try #require(subtitles.options.last)
        subtitles.select(french)
        #expect(engine.subtitleSelections.last == french.track)
        #expect(ExternalSubtitle.index(of: french.track) == 0)
    }

    // MARK: - Timing

    @Test func stepsAreTenthsWithoutDrift() {
        var delay: TimeInterval = 0
        for _ in 0..<15 { delay = SubtitleTiming.shifted(delay, by: 1) }
        #expect(delay == 1.5)
        #expect(SubtitleTiming.shifted(-0.1, by: 1) == 0)
        #expect(SubtitleTiming.shifted(0, by: -3) == -0.3)
        #expect(SubtitleTiming.shifted(SubtitleTiming.limit, by: 1) == SubtitleTiming.limit)
    }

    @Test func timingReadsWithItsSign() {
        #expect(SubtitleTiming.text(1.5) == "+1.5s")
        #expect(SubtitleTiming.text(-0.3) == "-0.3s")
        #expect(SubtitleTiming.text(0) == "0.0s")
    }

    @Test func aTimingChangeAppliesAtOnceAndPersistsForTheStream() throws {
        let suite = "AddonSubtitleTests.\(UUID().uuidString)"
        let engine = FakePlaybackEngine()
        let subtitles = try Self.subtitles(engine, delayKey: "tt1|a.mkv", delays: try Self.delayStore(suite: suite))
        for _ in 0..<15 { subtitles.shiftDelay(by: 1) }
        #expect(engine.subtitleDelay == 1.5)

        // The same stream reopens with it, read back from storage; another stream doesn't.
        let reopened = FakePlaybackEngine()
        let again = try Self.subtitles(reopened, delayKey: "tt1|a.mkv", delays: try Self.delayStore(suite: suite))
        #expect(again.delay == 1.5)
        #expect(reopened.subtitleDelay == 1.5)
        let otherEngine = FakePlaybackEngine()
        let other = try Self.subtitles(otherEngine, delayKey: "tt1|b.mkv", delays: try Self.delayStore(suite: suite))
        #expect(other.delay == 0)
    }

    @Test func resettingForgetsTheTiming() throws {
        let store = try Self.delayStore()
        let engine = FakePlaybackEngine()
        let subtitles = try Self.subtitles(engine, delayKey: "tt1|a.mkv", delays: store)
        subtitles.shiftDelay(by: 5)
        subtitles.resetDelay()
        #expect(store.delay(forStream: "tt1|a.mkv") == 0)
    }

    @Test func streamKeysPreferTheFilenameOverTheURL() {
        let url = URL(filePath: "/token123/file.mkv")
        #expect(SubtitleDelayStore.streamKey(contentID: "tt1:1:2", filename: "Show.S01E02.mkv", url: url)
            == "tt1:1:2|Show.S01E02.mkv")
        #expect(SubtitleDelayStore.streamKey(contentID: "tt1", filename: nil, url: url) == "tt1|\(url.absoluteString)")
    }
}
