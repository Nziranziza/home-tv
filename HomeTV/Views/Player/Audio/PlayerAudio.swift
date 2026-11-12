import Foundation
import Observation

/// The player's audio tracks. Opens on `AudioDefaults`' pick and remembers the viewer's choice per show.
@Observable
@MainActor
final class PlayerAudio {
    private(set) var options: [AudioTrackOption] = []
    private(set) var track: PlaybackTrack?

    @ObservationIgnored private unowned let engine: any PlaybackEngine
    @ObservationIgnored private let store: AudioChoiceStore
    @ObservationIgnored private let showID: String?
    @ObservationIgnored private let deviceLanguage: String
    /// This play's choice, kept over a decoder restart even when there's no show to save it against.
    @ObservationIgnored private var choice: AudioChoice?

    init(
        engine: any PlaybackEngine,
        showID: String?,
        store: AudioChoiceStore = .shared,
        deviceLanguage: String = SubtitleLanguage.device
    ) {
        self.engine = engine
        self.showID = showID
        self.store = store
        self.deviceLanguage = deviceLanguage
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

    func select(_ option: AudioTrackOption) {
        guard option.track.id != track?.id else { return }
        track = option.track
        engine.select(option.track)
        let choice = AudioChoice(track: option.track)
        self.choice = choice
        updatePicker()
        if let showID { store.record(choice, forShow: showID) }
    }

    private func updatePicker() {
        let choice = choice
        let deviceLanguage = deviceLanguage
        engine.audioPicker = { tracks in
            AudioDefaults.track(in: tracks, deviceLanguage: deviceLanguage, remembered: choice)
        }
    }
}
