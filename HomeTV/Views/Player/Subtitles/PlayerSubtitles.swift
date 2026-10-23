import Foundation
import Observation

/// The player's subtitle state: the stream's tracks, On or Off, the chosen language, and the caption style.
/// Picks the opening subtitles with `SubtitleDefaults` and remembers the viewer's choice per show.
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

    @ObservationIgnored private unowned let engine: any PlaybackEngine
    @ObservationIgnored private let store: SubtitleChoiceStore
    @ObservationIgnored private let showID: String?
    @ObservationIgnored private let deviceLanguage: String
    @ObservationIgnored private var forcedTrack: PlaybackTrack?
    /// This play's choice, kept over a decoder restart even when there's no show to save it against.
    @ObservationIgnored private var choice: SubtitleChoice?

    init(
        engine: any PlaybackEngine,
        showID: String?,
        store: SubtitleChoiceStore = .shared,
        deviceLanguage: String = SubtitleLanguage.device
    ) {
        self.engine = engine
        self.showID = showID
        self.store = store
        self.deviceLanguage = deviceLanguage
    }

    /// The name the Language row shows.
    var trackName: String? {
        options.first { $0.id == track?.id }?.name
    }

    var activeStyleName: String? {
        styles.first { $0.id == activeStyleID }?.name
    }

    /// The engine has listed the stream's tracks: picks the opening subtitles.
    func tracksDidLoad() {
        let tracks = engine.tracks(of: .subtitle)
        let regular = tracks.filter { !$0.isForced }
        options = zip(regular, SubtitleTrackName.names(for: regular)).map(SubtitleTrackOption.init)
        let audio = engine.tracks(of: .audio)
        let audioLanguage = (audio.first(where: \.isSelected) ?? audio.first)?.languageCode
        let selection = SubtitleDefaults.selection(
            for: tracks,
            audioLanguage: audioLanguage,
            deviceLanguage: deviceLanguage,
            remembered: choice ?? showID.flatMap(store.choice(forShow:))
        )
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

    private func choose(_ track: PlaybackTrack, isOn: Bool) {
        self.track = track
        self.isOn = isOn
        engine.selectSubtitle(track)
        remember()
    }

    private func remember() {
        let choice = SubtitleChoice(isOn: isOn, languageCode: track?.languageCode, isSDH: track?.isSDH ?? false)
        self.choice = choice
        if let showID { store.record(choice, forShow: showID) }
    }
}
