import Foundation
import Testing
@testable import HomeTV

/// Which subtitles a title opens with, and how a choice carries to the next episode.
@MainActor
struct SubtitleDefaultsTests {

    static func track(
        _ id: Int32,
        _ language: String?,
        forced: Bool = false,
        sdh: Bool = false,
        name: String = ""
    ) -> PlaybackTrack {
        PlaybackTrack(
            id: id, kind: .subtitle, name: name, languageCode: language, isSelected: false,
            isForced: forced, isSDH: sdh
        )
    }

    static let english = track(1, "eng")
    static let englishSDH = track(2, "eng", sdh: true)
    static let englishForced = track(3, "eng", forced: true)
    static let french = track(4, "fre")
    static let korean = track(5, "kor")

    static func selection(
        _ tracks: [PlaybackTrack],
        audio: String?,
        device: String = "en-US",
        remembered: SubtitleChoice? = nil
    ) -> SubtitleDefaults.Selection {
        SubtitleDefaults.selection(for: tracks, audioLanguage: audio, deviceLanguage: device, remembered: remembered)
    }

    // MARK: - Opening defaults

    @Test func audioInTheDeviceLanguageOpensWithSubtitlesOff() {
        let selection = Self.selection([Self.english, Self.french], audio: "eng")
        #expect(!selection.isOn)
        #expect(selection.shown == nil)
        // On still has a track ready, in the device's language.
        #expect(selection.track == Self.english)
    }

    @Test func koreanAudioOnAnEnglishDeviceOpensWithEnglishSubtitles() {
        let selection = Self.selection([Self.korean, Self.english], audio: "kor")
        #expect(selection.isOn)
        #expect(selection.shown == Self.english)
    }

    @Test func foreignAudioWithNoDeviceLanguageTrackStaysOff() {
        let selection = Self.selection([Self.korean, Self.french], audio: "kor")
        #expect(!selection.isOn)
    }

    @Test func unknownAudioLanguageStaysOff() {
        #expect(!Self.selection([Self.english], audio: nil).isOn)
        #expect(!Self.selection([Self.english], audio: "und").isOn)
    }

    @Test func plainSubtitlesComeBeforeSDH() {
        let selection = Self.selection([Self.englishSDH, Self.english, Self.korean], audio: "kor")
        #expect(selection.shown == Self.english)
    }

    @Test func bibliographicCodesMatchTheDeviceLanguage() {
        let selection = Self.selection([Self.english, Self.french], audio: "eng", device: "fr-FR")
        #expect(selection.isOn)
        #expect(selection.shown == Self.french)
    }

    // MARK: - Forced subtitles

    @Test func forcedSubtitlesShowWhileOff() {
        let selection = Self.selection([Self.englishForced, Self.english], audio: "eng")
        #expect(!selection.isOn)
        #expect(selection.shown == Self.englishForced)
    }

    @Test func forcedTracksAreNeverTheChosenLanguage() {
        let selection = Self.selection([Self.englishForced, Self.korean], audio: "kor")
        #expect(selection.track == Self.korean)
        #expect(!selection.isOn)
    }

    @Test func forcedSubtitlesInTheAudioLanguageWinOverTheDevices() {
        let frenchForced = Self.track(6, "fra", forced: true)
        let selection = Self.selection([Self.englishForced, frenchForced], audio: "fre")
        #expect(selection.forcedTrack == frenchForced)
    }

    // MARK: - Remembered choices

    @Test func aRememberedLanguageWinsOverTheDefault() {
        let remembered = SubtitleChoice(isOn: true, languageCode: "fre")
        let selection = Self.selection([Self.english, Self.french], audio: "eng", remembered: remembered)
        #expect(selection.shown == Self.french)
    }

    @Test func aRememberedOffWinsOverForeignAudio() {
        let remembered = SubtitleChoice(isOn: false, languageCode: "eng")
        let selection = Self.selection([Self.korean, Self.english], audio: "kor", remembered: remembered)
        #expect(!selection.isOn)
    }

    @Test func aRememberedSDHChoiceKeepsSDH() {
        let remembered = SubtitleChoice(isOn: true, languageCode: "eng", isSDH: true)
        let selection = Self.selection([Self.english, Self.englishSDH], audio: "eng", remembered: remembered)
        #expect(selection.shown == Self.englishSDH)
    }

    @Test func aRememberedLanguageTheEpisodeLacksFallsBackToTheDevices() {
        let remembered = SubtitleChoice(isOn: true, languageCode: "ger")
        let selection = Self.selection([Self.french, Self.english], audio: "eng", remembered: remembered)
        #expect(selection.shown == Self.english)
    }

    // MARK: - Carry-over

    static func subtitles(
        _ engine: FakePlaybackEngine,
        showID: String?,
        store: SubtitleChoiceStore
    ) -> PlayerSubtitles {
        PlayerSubtitles(engine: engine, showID: showID, store: store, deviceLanguage: "en-US")
    }

    static func store() throws -> SubtitleChoiceStore {
        let suite = "SubtitleDefaultsTests.\(UUID().uuidString)"
        return SubtitleChoiceStore(defaults: try #require(UserDefaults(suiteName: suite)))
    }

    @Test func aChoiceInOneEpisodeCarriesToTheNext() throws {
        let store = try Self.store()
        let episode1 = FakePlaybackEngine()
        episode1.subtitleTracks = [Self.english, Self.french]
        episode1.audioTracks = [PlaybackTrack(id: 1, kind: .audio, name: "", languageCode: "eng", isSelected: true)]
        let first = Self.subtitles(episode1, showID: "tt0903747", store: store)
        first.tracksDidLoad()
        #expect(episode1.subtitleSelections.last == .some(nil))
        let french = try #require(first.options.first { $0.track == Self.french })
        first.select(french)

        // The next episode's tracks have their own ids.
        let episode2 = FakePlaybackEngine()
        let nextFrench = Self.track(14, "fre")
        episode2.subtitleTracks = [Self.track(11, "eng"), nextFrench]
        episode2.audioTracks = episode1.audioTracks
        let second = Self.subtitles(episode2, showID: "tt0903747", store: store)
        second.tracksDidLoad()
        #expect(second.isOn)
        #expect(episode2.subtitleSelections.last == nextFrench)
    }

    @Test func turningSubtitlesOffCarriesToo() throws {
        let store = try Self.store()
        let engine = FakePlaybackEngine()
        engine.subtitleTracks = [Self.korean, Self.english]
        engine.audioTracks = [PlaybackTrack(id: 1, kind: .audio, name: "", languageCode: "kor", isSelected: true)]
        let first = Self.subtitles(engine, showID: "show", store: store)
        first.tracksDidLoad()
        #expect(first.isOn)
        first.turnOff()

        let second = Self.subtitles(engine, showID: "show", store: store)
        second.tracksDidLoad()
        #expect(!second.isOn)
    }

    @Test func aDecoderRestartKeepsThisPlaysChoice() throws {
        let engine = FakePlaybackEngine()
        engine.subtitleTracks = [Self.english, Self.french]
        let subtitles = Self.subtitles(engine, showID: nil, store: try Self.store())
        subtitles.tracksDidLoad()
        let french = try #require(subtitles.options.first { $0.track == Self.french })
        subtitles.select(french)
        subtitles.tracksDidLoad()
        #expect(engine.subtitleSelections.last == Self.french)
    }

    // MARK: - Names

    static let en = Locale(identifier: "en_US")

    @Test func namesSpellOutTheLanguageAndSDH() {
        #expect(SubtitleTrackName.name(for: Self.englishSDH, locale: Self.en) == "English SDH")
        #expect(SubtitleTrackName.name(for: Self.track(7, "zh-Hans", sdh: true), locale: Self.en) == "Chinese, Simplified SDH")
        #expect(SubtitleTrackName.name(for: Self.french, locale: Self.en) == "French")
    }

    @Test func aTrackWithNoLanguageUsesItsTitle() {
        #expect(SubtitleTrackName.name(for: Self.track(8, nil, name: "Commentary"), locale: Self.en) == "Commentary")
        #expect(SubtitleTrackName.name(for: Self.track(9, "und"), locale: Self.en) == "Unknown language")
    }

    @Test func sharedNamesAddTheTracksTitle() {
        let tracks = [Self.track(1, "eng", name: "Signs"), Self.track(2, "eng", name: "Full")]
        #expect(SubtitleTrackName.names(for: tracks, locale: Self.en) == ["English (Signs)", "English (Full)"])
    }

    @Test func theMenuLeavesOutForcedTracks() throws {
        let engine = FakePlaybackEngine()
        engine.subtitleTracks = [Self.englishForced, Self.english]
        let subtitles = Self.subtitles(engine, showID: nil, store: try Self.store())
        subtitles.tracksDidLoad()
        #expect(subtitles.options.map(\.track) == [Self.english])
    }
}
