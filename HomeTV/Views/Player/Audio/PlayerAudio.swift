import Foundation
import Observation

/// The player's audio tracks and adjustments. Opens on `AudioDefaults`' pick and remembers the viewer's
/// choice per show; the adjustments are kept for every title.
@Observable
@MainActor
final class PlayerAudio {
    private(set) var options: [AudioTrackOption] = []
    private(set) var track: PlaybackTrack?
    private(set) var adjustments: AudioAdjustments {
        didSet {
            engine.audioAdjustments = adjustments
            adjustmentsStore.adjustments = adjustments
        }
    }

    /// False for audio passed through undecoded, which the rows then say.
    var canAdjust: Bool { engine.canAdjustAudio }

    @ObservationIgnored private unowned let engine: any PlaybackEngine
    @ObservationIgnored private let store: AudioChoiceStore
    @ObservationIgnored private let adjustmentsStore: AudioAdjustmentsStore
    @ObservationIgnored private let showID: String?
    @ObservationIgnored private let deviceLanguage: String
    /// This play's choice, kept over a decoder restart even when there's no show to save it against.
    @ObservationIgnored private var choice: AudioChoice?

    init(
        engine: any PlaybackEngine,
        showID: String?,
        store: AudioChoiceStore = .shared,
        adjustmentsStore: AudioAdjustmentsStore = .shared,
        deviceLanguage: String = SubtitleLanguage.device
    ) {
        self.engine = engine
        self.showID = showID
        self.store = store
        self.adjustmentsStore = adjustmentsStore
        self.deviceLanguage = deviceLanguage
        adjustments = adjustmentsStore.adjustments
        engine.audioAdjustments = adjustments
        choice = showID.flatMap(store.choice(forShow:))
        updatePicker()
    }

    /// The engine has listed the stream's tracks: switches to the pick if the engine opened another.
    func tracksDidLoad() {
        let tracks = engine.tracks(of: .audio)
        options = AudioTrackName.options(for: tracks)
        let pick = AudioDefaults.track(in: tracks, deviceLanguage: deviceLanguage, remembered: choice)
        track = pick
        if let pick, !pick.isSelected { engine.select(pick) }
    }

    /// A prepared play starting: picks up what the viewer changed in the play before it since it opened.
    /// True when that switched the track.
    @discardableResult
    func reloadSaved() -> Bool {
        if adjustments != adjustmentsStore.adjustments { adjustments = adjustmentsStore.adjustments }
        guard let saved = showID.flatMap(store.choice(forShow:)), saved != choice else { return false }
        choice = saved
        updatePicker()
        guard !options.isEmpty else { return false }
        let previous = track?.id
        tracksDidLoad()
        return track?.id != previous
    }

    func select(_ option: AudioTrackOption) {
        guard option.track.id != track?.id else { return }
        track = option.track
        engine.select(option.track)
        let choice = AudioChoice(track: option.track)
        self.choice = choice
        updatePicker()
        if let showID { store.record(choice, forShow: showID) }
    }

    func setDialogue(_ dialogue: AudioAdjustments.DialogueEnhancement) {
        adjustments.dialogue = dialogue
    }

    func toggleReduceLoudSounds() {
        adjustments.reducesLoudSounds.toggle()
    }

    private func updatePicker() {
        let choice = choice
        let deviceLanguage = deviceLanguage
        engine.audioPicker = { tracks in
            AudioDefaults.track(in: tracks, deviceLanguage: deviceLanguage, remembered: choice)
        }
    }
}
