import Foundation
import Observation

/// The player's subtitle state: the stream's tracks and the add-on's files, On or Off, the chosen
/// language, the caption style and the timing. Picks the opening subtitles with `SubtitleDefaults` and
/// remembers the viewer's choice per show, and the timing per stream.
@Observable
@MainActor
final class PlayerSubtitles {
    /// The tracks the Language menu lists. Forced tracks are left out; they show on their own.
    private(set) var options: [SubtitleTrackOption] = []
    private(set) var isOn = false
    /// The track On shows.
    private(set) var track: PlaybackTrack?
    private(set) var styles: [CaptionStyle] = []
    private(set) var activeStyleID: String?
    /// The active style's look, for the preview.
    private(set) var appearance: CaptionAppearance?
    /// Seconds the subtitles are shifted by. Positive shows them later.
    private(set) var delay: TimeInterval

    @ObservationIgnored private unowned let engine: any PlaybackEngine
    @ObservationIgnored private let store: SubtitleChoiceStore
    @ObservationIgnored private let showID: String?
    @ObservationIgnored private let delays: SubtitleDelayStore
    @ObservationIgnored private let delayKey: String?
    @ObservationIgnored private let deviceLanguage: String
    @ObservationIgnored private var forcedTrack: PlaybackTrack?
    /// This play's choice, kept over a decoder restart even when there's no show to save it against.
    @ObservationIgnored private var choice: SubtitleChoice?
    /// The exact track picked this play, so a restart can't swap it for another in the same language.
    @ObservationIgnored private var chosenTrack: PlaybackTrack?

    init(
        engine: any PlaybackEngine,
        showID: String?,
        store: SubtitleChoiceStore = .shared,
        delayKey: String? = nil,
        delays: SubtitleDelayStore = .shared,
        deviceLanguage: String = SubtitleLanguage.device
    ) {
        self.engine = engine
        self.showID = showID
        self.store = store
        self.delayKey = delayKey
        self.delays = delays
        self.deviceLanguage = deviceLanguage
        delay = delayKey.map(delays.delay(forStream:)) ?? 0
        engine.subtitleDelay = delay
    }

    /// The name the Language row shows.
    var trackName: String? {
        options.first { $0.id == track?.id }?.name
    }

    var activeStyleName: String? {
        styles.first { $0.id == activeStyleID }?.name
    }

    /// The engine has listed the stream's tracks: picks the opening subtitles. `audioTrack` is the audio
    /// being switched to, else the engine's selected track counts.
    func tracksDidLoad(audioTrack: PlaybackTrack? = nil) {
        let all = engine.tracks(of: .subtitle)
        let regular = SubtitleTrackList.tracks(
            embedded: all.filter { !$0.isExternal && !$0.isForced },
            external: all.filter(\.isExternal),
            deviceLanguage: deviceLanguage
        )
        let tracks = regular + all.filter(\.isForced)
        options = zip(regular, SubtitleTrackName.names(for: regular)).map(SubtitleTrackOption.init)
        let audio = engine.tracks(of: .audio)
        let audioLanguage = (audioTrack ?? audio.first(where: \.isSelected) ?? audio.first)?.languageCode
        var selection = SubtitleDefaults.selection(
            for: tracks,
            audioLanguage: audioLanguage,
            deviceLanguage: deviceLanguage,
            remembered: choice ?? showID.flatMap(store.choice(forShow:))
        )
        if let chosenTrack, let same = regular.first(where: { Self.isSame($0, chosenTrack) }) {
            selection.track = same
        }
        isOn = selection.isOn
        track = selection.track
        forcedTrack = selection.forcedTrack
        engine.selectSubtitle(selection.shown)
    }

    func turnOn() {
        guard let track else { return }
        choose(track, isOn: true)
    }

    func turnOff() {
        isOn = false
        engine.selectSubtitle(forcedTrack)
        remember()
    }

    /// A language picked in the menu, which also turns subtitles on.
    func select(_ option: SubtitleTrackOption) {
        choose(option.track, isOn: true)
    }

    /// Reads the system styles, which can change in Settings while the player is closed.
    func loadStyles() {
        styles = CaptionStyles.all()
        activeStyleID = CaptionStyles.activeID
        appearance = CaptionAppearance.active()
    }

    func selectStyle(_ style: CaptionStyle) {
        CaptionStyles.activate(style.id)
        loadStyles()
    }

    /// Left or Right on Timing: a tenth of a second later or earlier per step, applied at once.
    func shiftDelay(by steps: Int) {
        setDelay(SubtitleTiming.shifted(delay, by: steps))
    }

    func resetDelay() {
        setDelay(0)
    }

    private func setDelay(_ delay: TimeInterval) {
        guard delay != self.delay else { return }
        self.delay = delay
        engine.subtitleDelay = delay
        if let delayKey { delays.record(delay, forStream: delayKey) }
    }

    private func choose(_ track: PlaybackTrack, isOn: Bool) {
        self.track = track
        chosenTrack = track
        self.isOn = isOn
        engine.selectSubtitle(track)
        remember()
    }

    /// The same stream's track, as relisted after a restart.
    private static func isSame(_ lhs: PlaybackTrack, _ rhs: PlaybackTrack) -> Bool {
        lhs.id == rhs.id && lhs.languageCode == rhs.languageCode && lhs.name == rhs.name
    }

    private func remember() {
        let choice = SubtitleChoice(
            isOn: isOn,
            languageCode: track?.languageCode,
            isSDH: track?.isSDH ?? false,
            name: track?.name
        )
        self.choice = choice
        if let showID { store.record(choice, forShow: showID) }
    }
}
