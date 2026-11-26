import Foundation
import Observation

/// The player's subtitle state: the stream's tracks and the add-on's files, On or Off, the chosen
/// language, the caption style and the timing. Picks the opening subtitles with `SubtitleDefaults` and
/// remembers the viewer's choice per show, and the timing per stream.
@Observable
@MainActor
final class PlayerSubtitles {
    /// The tracks the Language menu lists. Forced tracks are left out; they show on their own.
    private(set) var options: [SubtitleTrackOption] = [] {
        didSet { fileLanguages = Self.fileLanguages(in: options, locale: locale) }
    }
    /// The add-on files' languages, each opening a page of its files.
    private(set) var fileLanguages: [SubtitleFileLanguage] = []
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
    /// The language tracks are named in.
    @ObservationIgnored private let locale: Locale
    /// The stream's file name, which add-on files are ranked against.
    @ObservationIgnored private let streamFilename: String?
    @ObservationIgnored private var forcedTrack: PlaybackTrack?
    /// This play's choice, kept over a decoder restart even when there's no show to save it against.
    @ObservationIgnored private var choice: SubtitleChoice?
    /// The exact track picked this play, so a restart can't swap it for another in the same language.
    @ObservationIgnored private var chosenTrack: PlaybackTrack?
    /// Set once the opening subtitles are picked; files arriving before then just join that pick.
    @ObservationIgnored private var hasOpened = false
    /// Add-on files listed at the opening pick; later ones arrived after it.
    @ObservationIgnored private var openingFileCount = 0
    /// The show's choice the opening pick was made from.
    @ObservationIgnored private var openingChoice: SubtitleChoice?

    init(
        engine: any PlaybackEngine,
        showID: String?,
        store: SubtitleChoiceStore = .shared,
        delayKey: String? = nil,
        delays: SubtitleDelayStore = .shared,
        deviceLanguage: String = SubtitleLanguage.device,
        locale: Locale = .current,
        streamFilename: String? = nil
    ) {
        self.streamFilename = streamFilename
        self.locale = locale
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

    /// The stream's own tracks, listed above the add-on languages.
    var streamOptions: [SubtitleTrackOption] {
        options.filter { !$0.track.isExternal }
    }

    func files(in languageCode: String?) -> [SubtitleTrackOption] {
        fileLanguages.first { $0.languageCode == languageCode }?.files ?? []
    }

    var activeStyleName: String? {
        styles.first { $0.id == activeStyleID }?.name
    }

    /// The engine has listed the stream's tracks: picks the opening subtitles. `audioTrack` is the audio
    /// being switched to, else the engine's selected track counts.
    func tracksDidLoad(audioTrack: PlaybackTrack? = nil) {
        let isRestart = hasOpened
        if !hasOpened { openingFileCount = engine.externalSubtitles.count }
        openingChoice = remembered
        hasOpened = true
        let (regular, tracks) = listTracks()
        var selection = defaultSelection(for: tracks, audioTrack: audioTrack, remembered: remembered)
        if let chosenTrack, let same = regular.first(where: { Self.isSame($0, chosenTrack) }) {
            selection.track = same
        }
        // A decoder restart doesn't let a file that arrived after the opening turn subtitles on by itself.
        if isRestart, choice == nil, !isOn, selection.isOn,
           let index = selection.track.flatMap(ExternalSubtitle.index(of:)), index >= openingFileCount {
            selection.isOn = false
        }
        isOn = selection.isOn
        track = selection.track
        forcedTrack = selection.forcedTrack
        engine.selectSubtitle(selection.shown)
    }

    /// A prepared play starting: picks again if the audio switched or the show's choice changed since it opened.
    func reloadSaved(audioTrack: PlaybackTrack?, audioDidSwitch: Bool) {
        let choiceChanged = remembered != openingChoice
        guard hasOpened, audioDidSwitch || choiceChanged else { return }
        // A track a late add-on file matched to the old choice; nothing is picked by hand before a prepared start.
        if choiceChanged, choice == nil { chosenTrack = nil }
        tracksDidLoad(audioTrack: audioTrack)
    }

    /// Subtitle add-on files arrived after the opening pick: lists them, keeping what's showing. They only
    /// switch subtitles on for the show's remembered choice, when one of them matches it better than
    /// anything at the opening, such as a remembered add-on English over the stream's English.
    func filesDidArrive() {
        guard hasOpened else { return }
        let (_, tracks) = listTracks()
        let selection = defaultSelection(for: tracks, audioTrack: nil, remembered: remembered)
        if choice == nil, let remembered = remembered, remembered.isOn,
           let pick = selection.track, SubtitleLanguage.matches(pick.languageCode, remembered.languageCode),
           !isOn || pick.id != track?.id {
            track = pick
            chosenTrack = pick
            isOn = true
            engine.selectSubtitle(pick)
        } else if track == nil {
            track = selection.track
        }
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

    /// Lists the menu's options. Returns them, then every track including forced ones.
    private func listTracks() -> (regular: [PlaybackTrack], all: [PlaybackTrack]) {
        let all = engine.tracks(of: .subtitle)
        let files = engine.externalSubtitles
        let regular = SubtitleTrackList.tracks(
            embedded: all.filter { !$0.isExternal && !$0.isForced },
            external: SubtitleFileRanking.ranked(
                all.filter(\.isExternal),
                files: files,
                streamFilename: streamFilename,
                frameRate: engine.videoFormat?.frameRate
            ),
            deviceLanguage: deviceLanguage,
            locale: locale
        )
        options = zip(regular, SubtitleTrackName.names(for: regular, locale: locale)).map { track, name in
            let file = ExternalSubtitle.index(of: track).flatMap { files.indices.contains($0) ? files[$0] : nil }
            return SubtitleTrackOption(track: track, name: name, detail: file?.releaseName)
        }
        return (regular, regular + all.filter(\.isForced))
    }

    /// The add-on files grouped by language, in list order.
    private static func fileLanguages(in options: [SubtitleTrackOption], locale: Locale) -> [SubtitleFileLanguage] {
        let files = options.filter(\.track.isExternal)
        var codes: [String?] = []
        for file in files where !codes.contains(file.track.languageCode) { codes.append(file.track.languageCode) }
        return codes.compactMap { code in
            let inLanguage = files.filter { $0.track.languageCode == code }
            guard let first = inLanguage.first else { return nil }
            let name = SubtitleTrackName.name(for: first.track, locale: locale)
            return SubtitleFileLanguage(languageCode: code, name: name, files: inLanguage)
        }
    }

    /// This play's choice, else the show's.
    private var remembered: SubtitleChoice? {
        choice ?? showID.flatMap(store.choice(forShow:))
    }

    private func defaultSelection(
        for tracks: [PlaybackTrack],
        audioTrack: PlaybackTrack?,
        remembered: SubtitleChoice?
    ) -> SubtitleDefaults.Selection {
        let audio = engine.tracks(of: .audio)
        return SubtitleDefaults.selection(
            for: tracks,
            audioLanguage: (audioTrack ?? audio.first(where: \.isSelected) ?? audio.first)?.languageCode,
            deviceLanguage: deviceLanguage,
            remembered: remembered
        )
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
            name: track?.name,
            isExternal: track?.isExternal
        )
        self.choice = choice
        if let showID { store.record(choice, forShow: showID) }
    }
}
