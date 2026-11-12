import Foundation
import Testing
@testable import HomeTV

/// Which audio track a title opens with, how the menu names tracks, and how a choice carries to the next
/// episode.
@MainActor
struct AudioDefaultsTests {

    static func track(
        _ id: Int32,
        _ language: String?,
        name: String = "",
        isDefault: Bool = false,
        original: Bool = false,
        dub: Bool = false,
        ad: Bool = false,
        codec: String? = nil,
        profile: String? = nil,
        channels: Int? = nil,
        selected: Bool = false
    ) -> PlaybackTrack {
        PlaybackTrack(
            id: id, kind: .audio, name: name, languageCode: language, isSelected: selected,
            isDefault: isDefault, isOriginal: original, isDub: dub, isAudioDescription: ad,
            codec: codec, codecProfile: profile, channelCount: channels
        )
    }

    static func pick(
        _ tracks: [PlaybackTrack],
        device: String = "en-US",
        remembered: AudioChoice? = nil
    ) -> PlaybackTrack? {
        AudioDefaults.track(in: tracks, deviceLanguage: device, remembered: remembered)
    }

    // MARK: - Opening defaults

    @Test func theOriginalLanguageWinsOverTheDevices() {
        let japanese = Self.track(1, "jpn", original: true)
        let english = Self.track(2, "eng", dub: true)
        #expect(Self.pick([english, japanese]) == japanese)
    }

    @Test func theDefaultTrackCountsAsOriginalUnlessItsADub() {
        let korean = Self.track(1, "kor", isDefault: true)
        let english = Self.track(2, "eng")
        #expect(Self.pick([english, korean]) == korean)

        let dubbed = Self.track(3, "kor", isDefault: true, dub: true)
        #expect(Self.pick([dubbed, english]) == english)
    }

    @Test func withNoFlagsTheDeviceLanguageWins() {
        let french = Self.track(1, "fre")
        let english = Self.track(2, "eng")
        #expect(Self.pick([french, english]) == english)
        #expect(Self.pick([french, english], device: "fr-CA") == french)
    }

    @Test func withNoMatchTheFirstTrackPlays() {
        let french = Self.track(1, "fre")
        let german = Self.track(2, "ger")
        #expect(Self.pick([french, german]) == french)
    }

    @Test func audioDescriptionIsNeverTheDefault() {
        let described = Self.track(1, "eng", isDefault: true, ad: true)
        let english = Self.track(2, "eng")
        #expect(Self.pick([described, english]) == english)
    }

    @Test func theFlaggedTrackWinsWithinTheOriginalLanguage() {
        let ac3 = Self.track(1, "eng", codec: "ac3", channels: 6)
        let trueHD = Self.track(2, "eng", isDefault: true, codec: "truehd", channels: 8)
        #expect(Self.pick([ac3, trueHD]) == trueHD)
    }

    // MARK: - Remembered choice

    @Test func aRememberedLanguageWinsOverTheOriginal() {
        let japanese = Self.track(1, "jpn", original: true)
        let english = Self.track(2, "eng")
        let choice = AudioChoice(track: Self.track(9, "eng"))
        #expect(Self.pick([japanese, english], remembered: choice) == english)
    }

    @Test func aRememberedFormatPicksBetweenSameLanguageTracks() {
        let trueHD = Self.track(1, "eng", isDefault: true, codec: "truehd", channels: 8)
        let ac3 = Self.track(2, "eng", codec: "ac3", channels: 6)
        let choice = AudioChoice(track: Self.track(9, "eng", codec: "ac3", channels: 6))
        #expect(Self.pick([trueHD, ac3], remembered: choice) == ac3)
    }

    @Test func aRememberedAudioDescriptionKeepsAudioDescription() {
        let english = Self.track(1, "eng", isDefault: true)
        let described = Self.track(2, "eng", ad: true)
        let choice = AudioChoice(track: Self.track(9, "eng", ad: true))
        #expect(Self.pick([english, described], remembered: choice) == described)
    }

    @Test func aRememberedLanguageTheEpisodeLacksFallsBackToTheOriginal() {
        let japanese = Self.track(1, "jpn", original: true)
        let english = Self.track(2, "eng")
        let choice = AudioChoice(track: Self.track(9, "spa"))
        #expect(Self.pick([english, japanese], remembered: choice) == japanese)
    }

    static func store() throws -> AudioChoiceStore {
        let suite = "AudioDefaultsTests.\(UUID().uuidString)"
        return AudioChoiceStore(defaults: try #require(UserDefaults(suiteName: suite)))
    }

    @Test func aChoiceInOneEpisodeCarriesToTheNext() throws {
        let store = try Self.store()
        let episode1 = FakePlaybackEngine()
        episode1.audioTracks = [Self.track(1, "jpn", original: true, selected: true), Self.track(2, "eng")]
        let first = PlayerAudio(engine: episode1, showID: "tt0903747", store: store, deviceLanguage: "en-US")
        first.tracksDidLoad()
        #expect(first.track?.id == 1)
        #expect(episode1.selections.isEmpty)
        let english = try #require(first.options.first { $0.id == 2 })
        first.select(english)
        #expect(episode1.selections.last?.id == 2)

        // The next episode's tracks have their own ids.
        let episode2 = FakePlaybackEngine()
        episode2.audioTracks = [Self.track(11, "jpn", original: true, selected: true), Self.track(12, "eng")]
        let second = PlayerAudio(engine: episode2, showID: "tt0903747", store: store, deviceLanguage: "en-US")
        // The engine opens on the pick when it can.
        #expect(episode2.audioPicker?(episode2.audioTracks)?.id == 12)
        second.tracksDidLoad()
        #expect(second.track?.id == 12)
        #expect(episode2.selections.last?.id == 12)
    }

    @Test func aDecoderRestartKeepsThisPlaysChoice() throws {
        let engine = FakePlaybackEngine()
        engine.audioTracks = [Self.track(1, "jpn", original: true, selected: true), Self.track(2, "eng")]
        let audio = PlayerAudio(engine: engine, showID: nil, store: try Self.store(), deviceLanguage: "en-US")
        audio.tracksDidLoad()
        audio.select(try #require(audio.options.last))
        #expect(engine.audioPicker?(engine.audioTracks)?.id == 2)
        audio.tracksDidLoad()
        #expect(audio.track?.id == 2)
    }

    // MARK: - Names

    static let en = Locale(identifier: "en_US")

    @Test func theOriginalLanguageIsLabelled() {
        let options = AudioTrackName.options(
            for: [Self.track(1, "eng", original: true), Self.track(2, "eng", ad: true), Self.track(3, "spa")],
            locale: Self.en
        )
        #expect(options.map(\.title) == ["Original: English", "Original: English AD", "Spanish"])
        #expect(options.allSatisfy { $0.detail == nil })
    }

    @Test func identicalTitlesShowCodecAndChannels() {
        let options = AudioTrackName.options(
            for: [
                Self.track(1, "eng", isDefault: true, codec: "truehd", channels: 8),
                Self.track(2, "eng", codec: "ac3", channels: 6),
            ],
            locale: Self.en
        )
        #expect(options.map(\.title) == ["Original: English", "Original: English"])
        #expect(options.map(\.detail) == ["TrueHD 7.1", "AC-3 5.1"])
    }

    @Test func identicalFormatsFallBackToTheTracksTitle() {
        let options = AudioTrackName.options(
            for: [
                Self.track(1, "eng", name: "Main", codec: "ac3", channels: 6),
                Self.track(2, "eng", name: "Commentary", codec: "ac3", channels: 6),
            ],
            locale: Self.en
        )
        #expect(options.map(\.detail) == ["Main", "Commentary"])
    }

    @Test func formatNamesSpellOutCodecsAndChannels() {
        #expect(AudioFormatName.codec("dts", profile: "DTS-HD MA") == "DTS-HD MA")
        #expect(AudioFormatName.codec("eac3", profile: nil) == "E-AC-3")
        #expect(AudioFormatName.codec("pcm_s24le", profile: nil) == "PCM")
        #expect(AudioFormatName.channels(2) == "Stereo")
        #expect(AudioFormatName.channels(6) == "5.1")
        #expect(AudioFormatName.label(for: Self.track(1, "eng")) == nil)
    }
}
