import Foundation
import Observation
import UIKit

/// Owns the playback engine for one `PlayerScreen`. Views read this, never the engine.
@Observable
@MainActor
final class PlayerModel {
    /// The remote's Left/Right skip.
    static let skipInterval: TimeInterval = 10
    /// How often the position is saved while playing; a force quit loses at most this much.
    static let saveInterval: Duration = .seconds(10)

    let request: PlayerRequest
    let bar: PlayerBarController
    let subtitles: PlayerSubtitles
    let audio: PlayerAudio
    /// The intro, recap and credits the Skip button offers.
    let skips: PlayerSkipSegments
    /// The open level of the Subtitles menu, nil while it's closed.
    private(set) var subtitlesMenu: SubtitlesMenuPage? {
        didSet { previousSubtitlesMenu = oldValue }
    }
    /// The level the Subtitles menu came from, so backing out lands on the row that opened it.
    @ObservationIgnored private(set) var previousSubtitlesMenu: SubtitlesMenuPage?
    /// The open level of the Audio menu, nil while it's closed.
    private(set) var audioMenu: AudioMenuPage? {
        didSet { previousAudioMenu = oldValue }
    }
    /// The level the Audio menu came from, so backing out lands on the row that opened it.
    @ObservationIgnored private(set) var previousAudioMenu: AudioMenuPage?
    var isAudioMenuOpen: Bool { audioMenu != nil }
    /// The tab panel up in place of the track, nil while the track shows.
    private(set) var panel: PlayerPanel?
    /// Continue Watching's one-click resume; its `resumingID` marks the card resolving.
    let resumer = ContinueWatchingResumer()
    /// The Info tab's poster, synopsis and genre, once loaded.
    private(set) var titleInfo: PlayerTitleInfo?
    /// The stream's quality badges, once its tracks are known.
    private(set) var badges: [PlayerBadge] = []
    @ObservationIgnored private let engine: any PlaybackEngine
    @ObservationIgnored private let nowPlaying: NowPlayingController?
    /// Set when the stream can't play, for the screen to show.
    private(set) var errorMessage: String?
    /// Set when playback reached its end, so the screen can close.
    private(set) var didFinish = false
    /// A scan or swipe in progress; the engine waits at its origin until it's committed or cancelled.
    private(set) var scrub: PlayerScrub?
    /// The skip glyph beside the time, briefly after a skip, as on the system player.
    private(set) var skipIndicator: PlayerScan.Direction?
    /// Counts skips, so the bar glides to each one.
    private(set) var skipCount = 0
    /// The latest skip, so loading after it shows on the same side.
    @ObservationIgnored private var lastSkip: (direction: PlayerScan.Direction, at: ContinuousClock.Instant)?
    @ObservationIgnored private var skipIndicatorTask: Task<Void, Never>?
    /// The scrub preview.
    let thumbnails: PlayerThumbnails
    @ObservationIgnored private let now: @MainActor () -> ContinuousClock.Instant
    /// The last seek, shown until the engine's clock reaches it, so quick repeated skips add up.
    private var lastSeek: (time: TimeInterval, at: ContinuousClock.Instant)?
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var isPrepared = false
    /// Saves a position (seconds) and runtime (seconds) for the request's item.
    @ObservationIgnored private let recordProgress: @MainActor (Int, Int, PlaybackItem) -> Void
    /// Set once the engine has played, so a stream that never started can't overwrite the resume point.
    @ObservationIgnored private var hasPlayed = false
    @ObservationIgnored private var lastSavedPosition: Int?
    /// Reports play, pause and finish to Trakt; a no-op while signed out.
    @ObservationIgnored private let scrobble: @MainActor (TraktScrobble) -> Void
    @ObservationIgnored private var lastScrobble: (action: TraktScrobble.Action, fraction: Double)?
    /// Manage Styles was chosen before playback started; pauses once it does.
    @ObservationIgnored private var pausesOnStart = false
    @ObservationIgnored private let loadTitleInfo: @MainActor (String, PlaybackItem) async -> PlayerTitleInfo?
    @ObservationIgnored private var titleInfoTask: Task<Void, Never>?
    @ObservationIgnored private let loadContinueWatching: @MainActor () -> [WatchHistoryItem]
    @ObservationIgnored private var resumeTask: Task<Void, Never>?
    /// The next episode, once resolved near the end.
    private(set) var upNext: UpNextEpisode?
    /// True while Up Next is due and not dismissed: the video sits in the corner over the next episode.
    private(set) var isShowingUpNext = false
    /// The countdown: seconds left in this episode.
    private(set) var upNextSecondsLeft = 0

    /// The countdown ring's remaining share, 1 when Up Next opens and 0 at the hand-over.
    var upNextCountdownFraction: Double {
        min(max(Double(upNextSecondsLeft) / upNextLead, 0), 1)
    }
    /// How long before the end Up Next shows: from the credits when known.
    @ObservationIgnored private var upNextLead = UpNextTiming.showLead
    /// Set once the viewer went back to full screen; the next episode still follows at the end.
    @ObservationIgnored private var isUpNextDismissed = false
    /// Set when Next Episode was chosen, so closing doesn't throw away the opened next stream.
    @ObservationIgnored private var rollsOver = false
    @ObservationIgnored private var hasPrewarmedUpNext = false
    @ObservationIgnored private(set) var upNextLoad: Task<Void, Never>?
    @ObservationIgnored private let loadUpNext: @MainActor (PlayerRequest) async throws -> UpNextEpisode?
    /// Failed lookups so far; a failure is retried after `upNextRetryDelay`, up to `UpNextTiming.maxAttempts`.
    @ObservationIgnored private var upNextAttempts = 0
    /// Set once the lookup has an answer, a next episode or none, or has given up. Until then an episode's
    /// credits are Up Next's, not Skip Credits'.
    private(set) var isUpNextSettled = false
    /// Credits pulled the lookup ahead of `UpNextTiming.resolveLead`; after early failures, one more
    /// round of attempts waits for that usual point.
    @ObservationIgnored private var lookupRound: UpNextLookupRound = .early
    /// The chapter read for the current tracks; a decoder restart replaces it.
    @ObservationIgnored private(set) var chapterLoad: Task<Void, Never>?
    @ObservationIgnored private let upNextRetryDelay: Duration
    @ObservationIgnored private let fetchAddonSubtitles: @MainActor (SubtitleAddonQuery) -> AsyncStream<[ExternalSubtitle]>
    /// The subtitle add-ons' lookup, started with the player and never waited on.
    @ObservationIgnored private(set) var addonSubtitleLoad: Task<Void, Never>?
    @ObservationIgnored private let prewarmer: PlayerPrewarmer

    init(
        request: PlayerRequest,
        engine: (any PlaybackEngine)? = nil,
        bar: PlayerBarController? = nil,
        publishesNowPlaying: Bool = true,
        recordProgress: (@MainActor (Int, Int, PlaybackItem) -> Void)? = nil,
        scrobble: (@MainActor (TraktScrobble) -> Void)? = nil,
        subtitleChoices: SubtitleChoiceStore = .shared,
        subtitleDelays: SubtitleDelayStore = .shared,
        audioChoices: AudioChoiceStore = .shared,
        loadTitleInfo: (@MainActor (String, PlaybackItem) async -> PlayerTitleInfo?)? = nil,
        loadContinueWatching: (@MainActor () -> [WatchHistoryItem])? = nil,
        loadUpNext: (@MainActor (PlayerRequest) async throws -> UpNextEpisode?)? = nil,
        upNextRetryDelay: Duration = UpNextTiming.retryDelay,
        prewarmer: PlayerPrewarmer? = nil,
        makeThumbnailer: (@MainActor (PlayerRequest) -> any PlaybackThumbnailer)? = nil,
        skipsSegments: Bool? = nil,
        loadSkipSegments: (@MainActor (SkipSegmentQuery) async -> [SkipSegmentSource])? = nil,
        fetchAddonSubtitles: (@MainActor (SubtitleAddonQuery) -> AsyncStream<[ExternalSubtitle]>)? = nil,
        now: @escaping @MainActor () -> ContinuousClock.Instant = { .now }
    ) {
        self.request = request
        let engine = engine ?? PlaybackEngines.make()
        engine.externalSubtitles = request.subtitles
        self.engine = engine
        self.bar = bar ?? PlayerBarController()
        let showID = request.item.map { SubtitleChoiceStore.showKey(forContentID: $0.contentID) }
        subtitles = PlayerSubtitles(
            engine: engine,
            showID: showID,
            store: subtitleChoices,
            delayKey: request.subtitleDelayKey,
            delays: subtitleDelays,
            streamFilename: request.subtitleQuery?.filename
        )
        audio = PlayerAudio(engine: engine, showID: showID, store: audioChoices)
        skips = PlayerSkipSegments(
            isEnabled: skipsSegments ?? PlayerPreference.shared.skipsSegments,
            fetch: loadSkipSegments ?? { await SkipSegmentClient.shared.sources(for: $0) }
        )
        nowPlaying = publishesNowPlaying ? NowPlayingController() : nil
        self.loadTitleInfo = loadTitleInfo ?? PlayerTitleInfoLoader.load
        self.loadContinueWatching = loadContinueWatching ?? { UserLibrary.continueWatchingItems }
        self.loadUpNext = loadUpNext ?? UpNextLoader.load
        self.upNextRetryDelay = upNextRetryDelay
        self.fetchAddonSubtitles = fetchAddonSubtitles ?? {
            SubtitleAddonFetcher.files(for: $0, in: AddonRegistry.shared.enabledAddons)
        }
        self.prewarmer = prewarmer ?? .shared
        self.now = now
        let makeThumbnailer = makeThumbnailer ?? { PlaybackThumbnailers.make(url: $0.url, headers: $0.headers) }
        thumbnails = PlayerThumbnails { makeThumbnailer(request) }
        self.recordProgress = recordProgress ?? { position, runtime, item in
            // A 0 only gets through after a seek back to the start.
            PlaybackProgress.record(
                position: position,
                runtime: runtime,
                item: item,
                isRestart: position == 0,
                scrobblesToTrakt: true
            )
        }
        self.scrobble = scrobble ?? { TraktService.shared.scrobble($0) }
    }

    var state: PlaybackState { engine.state }
    var videoView: UIView { engine.videoView }
    var currentTime: TimeInterval { engine.currentTime }
    var duration: TimeInterval { engine.duration }
    var isPlaying: Bool { engine.state == .playing || engine.state == .buffering }
    var isInfoOpen: Bool { panel == .info }

    /// The Continue Watching tab's cards: everything in progress except what's playing.
    var continueWatchingItems: [WatchHistoryItem] {
        let items = loadContinueWatching()
        guard let showID = request.item?.showID else { return items }
        return items.filter { $0.metaID != showID }
    }
    /// The detail screen Go to Movie / Go to Show opens; nil for a play that isn't a library title.
    var detail: MetaPreview? {
        guard let item = request.item else { return nil }
        return titleInfo?.detail ?? .placeholder(type: request.type, id: item.showID, name: request.title)
    }

    /// The Info tab's genre and runtime; the stream's own length once known.
    var infoLine: String? {
        let runtime = duration > 0 ? duration : titleInfo?.runtimeSeconds.map(TimeInterval.init)
        return PlayerInfoLine.text(genre: titleInfo?.genre, runtimeSeconds: runtime)
    }

    /// The time the bar shows: the scrub position while scrubbing.
    var displayTime: TimeInterval { scrub?.position(at: now()) ?? playheadTime }

    /// Where the played fill ends: real playback, or the scrub when it began from playback.
    var fillTime: TimeInterval {
        guard let scrub, scrub.isFromPlayback else { return playheadTime }
        return scrub.position(at: now())
    }

    var isScanning: Bool { scrub?.scan != nil }

    /// Buffering after playback began, shown as a spinner in the bar rather than the loading screen.
    var isLoadingInPlace: Bool { engine.state == .buffering && hasPlayed }

    /// The full-screen loading view: the first load, or a stall while the bar is hidden.
    var showsLoadingScreen: Bool {
        engine.state == .loading || (engine.state == .buffering && !(isLoadingInPlace && bar.isVisible))
    }

    var timeIndicator: PlayerTimeIndicator? {
        if let scan = scrub?.scan { return .scan(scan) }
        if isLoadingInPlace { return .loading(loadingSide) }
        if let skipIndicator { return .skip(skipIndicator) }
        return engine.state == .paused ? .paused : nil
    }

    /// A skip's side for a few seconds after it; otherwise after the time.
    private var loadingSide: PlayerScan.Direction {
        guard let lastSkip, ContinuousClock.now - lastSkip.at < .seconds(3) else { return .forward }
        return lastSkip.direction
    }

    /// The video's width over height, for the preview frame.
    var videoAspectRatio: Double {
        guard let size = engine.videoFormat?.size, size.width > 0, size.height > 0 else { return 16 / 9 }
        return size.width / size.height
    }

    /// The engine's clock, or the last seek until the clock reaches it. Given up after a second, in case
    /// the engine snapped to a keyframe elsewhere. The start time until the clock starts, so a resume
    /// never shows 00:00 first.
    private var playheadTime: TimeInterval {
        let time = currentTime
        if !hasPlayed, time == 0 { return request.startTime }
        if let lastSeek, abs(time - lastSeek.time) >= 1, ContinuousClock.now - lastSeek.at < .seconds(1) {
            return lastSeek.time
        }
        return time
    }

    /// Opens the stream ahead of Select, its tracks already picked, so `start` only has to play it.
    func prepare() {
        guard !isPrepared, !isStarted else { return }
        isPrepared = true
        loadSkipSegments()
        loadAddonSubtitles()
        attachEngine()
        engine.prepare(url: request.url, headers: request.headers, startTime: request.startTime)
    }

    /// A prepared play the viewer moved on from before Select.
    func discard() {
        guard !isStarted else { return }
        addonSubtitleLoad?.cancel()
        engine.stop()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        PlaybackAudioSession.configure()
        if isPrepared { reloadSavedChoices() } else { attachEngine() }
        loadSkipSegments()
        loadAddonSubtitles()
        if let item = request.item {
            titleInfoTask = Task { [weak self, type = request.type, loadTitleInfo] in
                let info = await loadTitleInfo(type, item)
                guard !Task.isCancelled else { return }
                self?.titleInfo = info
            }
        }
        engine.load(url: request.url, headers: request.headers, startTime: request.startTime)
        nowPlaying?.activate(title: request.title, commands: self)
    }

    private func attachEngine() {
        engine.onFinish = { [weak self] error in
            guard let self else { return }
            if error == nil {
                saveProgress(atEnd: true)
                report(.stop, atEnd: true)
                didFinish = true
            } else {
                errorMessage = Self.message(for: error)
            }
        }
        engine.onTracksReady = { [weak self] in
            guard let self else { return }
            // Audio first: the subtitles' default depends on the audio's language.
            audio.tracksDidLoad()
            subtitles.tracksDidLoad(audioTrack: audio.track)
            updateBadges()
            chapterLoad?.cancel()
            chapterLoad = Task { [weak self, engine] in
                let chapters = await engine.loadChapters()
                guard !Task.isCancelled else { return }
                self?.skips.chaptersDidLoad(chapters)
            }
        }
    }

    private func updateBadges() {
        badges = PlayerBadge.badges(
            video: engine.videoFormat,
            audio: engine.tracks(of: .audio),
            subtitles: engine.tracks(of: .subtitle)
        )
    }

    /// Audio and subtitle choices the viewer changed in the play before since this one was prepared.
    private func reloadSavedChoices() {
        let audioDidSwitch = audio.reloadSaved()
        subtitles.reloadSaved(audioTrack: audio.track, audioDidSwitch: audioDidSwitch)
        if audioDidSwitch { updateBadges() }
    }

    private func loadSkipSegments() {
        guard let item = request.item else { return }
        skips.load(SkipSegmentQuery(type: request.type, item: item))
    }

    private func loadAddonSubtitles() {
        guard addonSubtitleLoad == nil, let query = request.subtitleQuery else { return }
        let batches = fetchAddonSubtitles(query)
        addonSubtitleLoad = Task { [weak self] in
            for await files in batches {
                guard !Task.isCancelled, let self else { return }
                addonSubtitlesDidArrive(files)
            }
        }
    }

    /// Joins the stream's own add-on files after them, so the listed tracks keep their ids.
    private func addonSubtitlesDidArrive(_ files: [ExternalSubtitle]) {
        let merged = ExternalSubtitle.merged(engine.externalSubtitles, adding: files)
        guard merged.count > engine.externalSubtitles.count else { return }
        engine.externalSubtitles = merged
        subtitles.filesDidArrive()
    }

    /// Click and Play/Pause: toggles playback, or plays from the scrub position, and shows the bar.
    func togglePlayPause() {
        // Up Next holds the screen: play and pause the corner video without the bar.
        if isShowingUpNext, !bar.isVisible {
            if isPlaying { engine.pause() } else if engine.state == .paused { engine.play() }
            return
        }
        if scrub != nil {
            commitScrub()
            return
        }
        switch engine.state {
        case .paused:
            engine.play()
            bar.show(isPlaying: true)
        case .playing, .buffering:
            engine.pause()
            bar.show(isPlaying: false)
        default:
            break
        }
    }

    func play() {
        guard !isPlaying else { return }
        togglePlayPause()
    }

    func pause() {
        guard isPlaying else { return }
        togglePlayPause()
    }

    /// The remote's Play/Pause: stops a scan that began paused and stays there; otherwise as Select.
    func playPauseCommand() {
        if let scrub, scrub.scan != nil, !scrub.isFromPlayback {
            self.scrub?.stopScan(at: now())
            return
        }
        togglePlayPause()
    }

    /// Left/Right went down. During a scan it's a click that changes the level; returns true then, so
    /// the press isn't also taken as a skip or a hold.
    func arrowPressed(_ side: PlayerScan.Direction) -> Bool {
        guard isScanning else { return false }
        scrub?.click(side, at: now())
        return true
    }

    /// Left/Right held: fast-forward or rewind at the first level.
    func arrowHeld(_ side: PlayerScan.Direction) {
        beginScan(side)
    }

    /// Left/Right clicked: skips 10 seconds.
    func arrowClicked(_ side: PlayerScan.Direction) {
        skip(by: side.sign * Self.skipInterval)
    }

    /// Starts a scan, or a click on one already running. The engine pauses where it is; the scan moves a
    /// position along, since remote streams can't decode at 96×.
    func beginScan(_ direction: PlayerScan.Direction) {
        guard canSeek else { return }
        if scrub?.scan != nil {
            scrub?.click(direction, at: now())
        } else if scrub != nil {
            scrub?.startScan(direction, at: now())
        } else {
            let isFromPlayback = isPlaying
            scrub = PlayerScrub(
                origin: playheadTime,
                duration: duration,
                isFromPlayback: isFromPlayback,
                scan: PlayerScan(direction: direction),
                at: now()
            )
            if isFromPlayback { engine.pause() }
        }
        followScrub()
    }

    /// The end of a Now Playing seek: plays from where the scan reached.
    func endScan() {
        guard scrub != nil else { return }
        commitScrub()
    }

    /// Left/Right: ±10s from the playhead, or from the scrub position while scrubbing.
    func skip(by seconds: TimeInterval) {
        guard canSeek, !isScanning else { return }
        let target = clamped(displayTime + seconds)
        if scrub != nil {
            scrub?.move(to: target, at: now())
        } else {
            seekEngine(to: target)
        }
        skipCount += 1
        let direction: PlayerScan.Direction = seconds < 0 ? .backward : .forward
        lastSkip = (direction, .now)
        showSkipIndicator(direction)
        bar.show(isPlaying: isPlaying)
    }

    func seek(to time: TimeInterval) {
        guard canSeek else { return }
        // A scan from playback paused the engine; the seek ends it, so playback resumes.
        let resumes = scrub?.isFromPlayback == true
        let endsScrub = scrub != nil
        if endsScrub { endScrub() }
        seekEngine(to: clamped(time))
        if resumes { engine.play() }
        if endsScrub {
            bar.release(isPlaying: isPlaying)
        } else {
            bar.noteActivity(isPlaying: isPlaying)
        }
    }

    /// A horizontal swipe on the click pad, as a fraction of its width, at `speed` widths per second.
    /// Scrubs only while paused; a faster swipe covers more of the title.
    func scrub(byPadFraction fraction: Double, speed: Double = 0) {
        guard canSeek, !isScanning else { return }
        if scrub == nil {
            guard engine.state == .paused else { return }
            scrub = PlayerScrub(origin: playheadTime, duration: duration, isFromPlayback: false, at: now())
        }
        let seconds = SwipeScrub.seconds(forFraction: fraction, speed: speed, duration: duration)
        let target = displayTime + seconds
        scrub?.move(to: target, at: now())
        followScrub()
    }

    private func followScrub() {
        bar.hold()
        thumbnails.follow { [weak self] in self?.displayTime ?? 0 }
    }

    /// Select or Play during a scrub: plays from its position.
    private func commitScrub() {
        guard let scrub else { return }
        let target = scrub.position(at: now())
        endScrub()
        seekEngine(to: target)
        engine.play()
        bar.hide()
    }

    /// Menu: back to exactly where the scrub began, playing.
    private func cancelScrub() {
        endScrub()
        engine.play()
        bar.hide()
        publishNowPlaying()
    }

    private func endScrub() {
        scrub = nil
        thumbnails.stop()
    }

    private func showSkipIndicator(_ direction: PlayerScan.Direction) {
        skipIndicator = direction
        skipIndicatorTask?.cancel()
        skipIndicatorTask = Task { [weak self] in
            // The fade in plus the hold; the fade out follows.
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled else { return }
            self?.skipIndicator = nil
        }
    }

    func openSubtitlesMenu() {
        subtitles.loadStyles()
        subtitlesMenu = .root
        bar.hold()
    }

    func showSubtitlesMenu(_ page: SubtitlesMenuPage) {
        subtitlesMenu = page
    }

    func closeSubtitlesMenu() {
        subtitlesMenu = nil
        bar.release(isPlaying: isPlaying)
    }

    func openAudioMenu() {
        audioMenu = .root
        bar.hold()
    }

    func showAudioMenu(_ page: AudioMenuPage) {
        audioMenu = page
    }

    func closeAudioMenu() {
        audioMenu = nil
        bar.release(isPlaying: isPlaying)
    }

    /// Focus moved: a panel is up while focus is on its tab or inside it.
    func focusDidChange(to target: PlayerFocus?) {
        if let target { panel = target.panel }
        noteActivity()
    }

    func closePanel() {
        panel = nil
    }

    /// Go to Movie / Go to Show, here or on a Continue Watching card: closes the player on the title's page.
    func goToDetail(_ meta: MetaPreview) {
        saveProgress()
        PlayerPresenter.shared.goToDetail(meta)
    }

    /// A Continue Watching card: saves this title's position, then plays the card's with its last stream
    /// in place of this one. With no stream to reuse, opens the title's page to pick one.
    func resume(_ item: WatchHistoryItem) {
        guard resumeTask == nil else { return }
        saveProgress()
        bar.hold()
        resumeTask = Task { [weak self, resumer] in
            let outcome = await resumer.resume(item)
            guard let self, !Task.isCancelled else { return }
            resumeTask = nil
            switch outcome {
            case .launched:
                break
            case .chooseStream:
                goToDetail(item.preview)
            case .cancelled:
                bar.release(isPlaying: isPlaying)
            }
        }
    }

    /// From Beginning: plays from 00:00 and hides the bar.
    func playFromBeginning() {
        guard canSeek else { return }
        endScrub()
        panel = nil
        seekEngine(to: 0)
        engine.play()
        bar.hide()
    }

    /// Manage Styles: the system's caption styles are edited in Settings, which takes over the screen.
    func pauseForSettings() {
        if engine.state == .loading || engine.state == .idle { pausesOnStart = true }
        pause()
        closeSubtitlesMenu()
    }

    /// Menu: backs out of an open menu one level, else ends a scrub, else hides the bar. A scan that began
    /// paused stops first; a second Menu cancels. Returns false when the bar was already hidden, so the
    /// screen closes.
    func handleExit() -> Bool {
        if let page = audioMenu {
            switch page {
            case .root: closeAudioMenu()
            case .enhanceDialogue: audioMenu = .root
            }
            return true
        }
        if let page = subtitlesMenu {
            switch page {
            case .root: closeSubtitlesMenu()
            case .files: subtitlesMenu = .language
            case .language, .style: subtitlesMenu = .root
            }
            return true
        }
        if panel != nil {
            closePanel()
            return true
        }
        if let scrub {
            if scrub.scan != nil, !scrub.isFromPlayback {
                self.scrub?.stopScan(at: now())
            } else {
                cancelScrub()
            }
            return true
        }
        guard bar.isVisible else {
            if isShowingUpNext {
                dismissUpNext()
                return true
            }
            // As on the system player, Menu puts the Skip button away for this segment.
            guard skipSegment != nil else { return false }
            skips.dismiss()
            return true
        }
        bar.hide()
        return true
    }

    /// Any remote input while the bar is up.
    func noteActivity() {
        bar.noteActivity(isPlaying: isPlaying)
    }

    /// Keeps the bar's countdown and Now Playing in step with the engine.
    func playbackDidChange() {
        if engine.state == .playing { hasPlayed = true }
        if pausesOnStart, isPlaying {
            pausesOnStart = false
            pause()
            return
        }
        if engine.state == .paused {
            saveProgress()
            // A scan holds playback, it doesn't pause it.
            if scrub?.isFromPlayback != true { report(.pause) }
        } else if engine.state == .playing {
            report(.start)
        }
        if isPlaying {
            bar.noteActivity(isPlaying: true)
        } else if engine.state == .paused, !isShowingUpNext {
            bar.show(isPlaying: false)
        }
        publishNowPlaying()
    }

    func publishNowPlaying() {
        nowPlaying?.update(elapsed: playheadTime, duration: duration, isPlaying: isPlaying)
    }

    /// Saves where playback is, or the end once it played through. Repeats of the last save are skipped.
    func saveProgress(atEnd: Bool = false) {
        if engine.state == .playing { hasPlayed = true }
        guard let item = request.item, hasPlayed, !didFinish, duration > 0 else { return }
        let runtime = Int(duration)
        let position = atEnd ? runtime : Int(savedTime)
        // An unseeked 0 is a clock that hasn't caught up with the start time; after a seek it's a restart.
        guard position > 0 || lastSeek != nil, position != lastSavedPosition else { return }
        lastSavedPosition = position
        PlaybackDiagnostics.log("save \(position)/\(runtime)s \(item.contentID)")
        recordProgress(position, runtime, item)
    }

    func stop() {
        upNextLoad?.cancel()
        chapterLoad?.cancel()
        skips.cancel()
        addonSubtitleLoad?.cancel()
        // Accepted, the next screen has already taken the opened stream.
        if hasPrewarmedUpNext, !rollsOver { prewarmer.cancel() }
        pausesOnStart = false
        subtitlesMenu = nil
        audioMenu = nil
        panel = nil
        titleInfoTask?.cancel()
        resumeTask?.cancel()
        skipIndicatorTask?.cancel()
        scrub = nil
        thumbnails.close()
        saveProgress()
        reportEnd()
        nowPlaying?.deactivate()
        bar.hide()
        engine.stop()
    }

    /// The app left or regained the foreground: a backgrounded play is paused on Trakt, and resumed when
    /// the app comes back still playing.
    func sceneDidChange(isActive: Bool) {
        if isActive {
            if engine.state == .playing { report(.start) }
        } else {
            saveProgress()
            report(.pause)
        }
    }

    // MARK: - Skip

    /// The segment the Skip button offers. Up Next stands in for an episode's credits until the lookup
    /// settles without a next one, and nothing shows while the viewer is scanning, scrubbing, in a menu,
    /// or can't seek.
    var skipSegment: SkipSegment? {
        guard let segment = skips.active, canSeek, scrub == nil, subtitlesMenu == nil, !isAudioMenuOpen,
              panel == nil, !isShowingUpNext else { return nil }
        if segment.kind == .credits, request.continuation != nil, upNext != nil || !isUpNextSettled { return nil }
        return segment
    }

    /// Called every second and after each seek: follows the playhead in and out of segments.
    func tickSkip() {
        guard duration > 0 else { return }
        skips.update(time: playheadTime, duration: duration)
    }

    /// Skip: past the segment or to the scene after the credits. Credits that run to the end finish
    /// playback as playing through would.
    func skipCurrentSegment() {
        guard let shown = skipSegment else { return }
        // Chapters may have arrived since the last tick; a changed segment only refreshes the button.
        tickSkip()
        guard let segment = skipSegment, segment == shown else { return }
        skips.dismiss()
        if segment.scene == nil, segment.end >= duration - 1 {
            saveProgress(atEnd: true)
            report(.stop, atEnd: true)
            didFinish = true
        } else {
            // Exact, or a keyframe before the end lands back in the segment.
            seekEngine(to: segment.target, isAccurate: true)
        }
    }

    // MARK: - Up Next

    /// What to play once this screen finishes: the next episode whenever there is one. Only closing the
    /// player stops it.
    var nextRequest: PlayerRequest? { upNext?.request }

    /// Called every second: resolves the next episode near the end, then shows Up Next and opens its
    /// stream so the hand-over has no black gap.
    func tickUpNext() {
        guard request.continuation != nil, hasPlayed, !didFinish, duration > 0 else { return }
        let remaining = duration - playheadTime
        let credits = skips.credits(duration: duration)
        // Held while Up Next is up, so credits arriving late can't close it from under the viewer.
        if !isShowingUpNext {
            upNextLead = UpNextTiming.showLead(creditsStart: credits?.start, duration: duration)
        }
        if lookupRound == .awaitingLate, remaining <= UpNextTiming.resolveLead {
            lookupRound = .late
            upNextAttempts = 0
            upNextLoad = nil
        }
        // Credits already playing, as after a resume into them, need their answer now.
        let isInCredits = credits.map { playheadTime >= $0.start } ?? false
        if upNextLoad == nil, UpNextTiming.isResolveDue(remaining: remaining, showLead: upNextLead) || isInCredits {
            upNextAttempts += 1
            upNextLoad = Task { [weak self, request, loadUpNext, upNextAttempts, upNextRetryDelay] in
                do {
                    let next = try await loadUpNext(request)
                    guard !Task.isCancelled else { return }
                    self?.upNext = next
                    self?.isUpNextSettled = true
                } catch {
                    // A failed request: clearing the lookup lets a later tick try again.
                    guard upNextAttempts < UpNextTiming.maxAttempts else {
                        if !Task.isCancelled { self?.upNextAttemptsRanOut() }
                        return
                    }
                    guard (try? await Task.sleep(for: upNextRetryDelay)) != nil else { return }
                    self?.upNextLoad = nil
                }
            }
        }
        guard let upNext, !isUpNextDismissed, UpNextTiming.isShowDue(remaining: remaining, showLead: upNextLead) else {
            if isShowingUpNext { isShowingUpNext = false }
            return
        }
        let secondsLeft = UpNextTiming.secondsLeft(remaining: remaining)
        if upNextSecondsLeft != secondsLeft { upNextSecondsLeft = secondsLeft }
        if !isShowingUpNext { isShowingUpNext = true }
        if !hasPrewarmedUpNext {
            hasPrewarmedUpNext = true
            prewarmer.prewarm(upNext.request)
        }
    }

    /// The last attempt failed: early ones get another round at the usual point, else the lookup gives up.
    private func upNextAttemptsRanOut() {
        if lookupRound == .early, duration - playheadTime > UpNextTiming.resolveLead {
            lookupRound = .awaitingLate
        } else {
            isUpNextSettled = true
        }
    }

    /// Next Episode: this episode counts as finished, and the screen moves on to the next.
    func playUpNext() {
        guard upNext != nil, !didFinish else { return }
        rollsOver = true
        isShowingUpNext = false
        saveProgress(atEnd: true)
        report(.stop, atEnd: true)
        didFinish = true
    }

    /// Selecting the corner video, or Menu: the video returns to full screen for the rest of the credits. The
    /// next episode still plays at the end, from the stream already opened.
    func dismissUpNext() {
        isUpNextDismissed = true
        isShowingUpNext = false
    }

    /// The playhead to save. A seek still in flight, however slow, is where the user is.
    private var savedTime: TimeInterval {
        engine.isSeeking ? lastSeek?.time ?? playheadTime : playheadTime
    }

    /// Ends the play on Trakt: `stop` if it's finished, otherwise `pause`.
    private func reportEnd() {
        guard duration > 0 else { return }
        report(TraktScrobble.endAction(forFraction: savedTime / duration))
    }

    /// Sends one scrobble for what's playing. Nothing before the stream has played, nothing after a
    /// `stop`, and no repeat of the last report.
    private func report(_ action: TraktScrobble.Action, atEnd: Bool = false) {
        guard let item = request.item, hasPlayed, duration > 0, lastScrobble?.action != .stop else { return }
        let fraction = atEnd ? 1 : min(max(savedTime / duration, 0), 1)
        if let lastScrobble, lastScrobble.action == action,
           action == .start || abs(lastScrobble.fraction - fraction) < 0.0001 { return }
        lastScrobble = (action, fraction)
        scrobble(TraktScrobble(action: action, item: item, type: request.type, title: request.title, fraction: fraction))
    }

    private func seekEngine(to time: TimeInterval, isAccurate: Bool = false) {
        lastSeek = (time, .now)
        engine.seek(to: time, isAccurate: isAccurate)
        publishNowPlaying()
        tickSkip()
    }

    private var canSeek: Bool { duration > 0 && engine.state != .failed && engine.state != .ended }

    private func clamped(_ time: TimeInterval) -> TimeInterval {
        min(max(0, time), duration)
    }

    nonisolated static func message(for error: (any Error)?) -> String {
        // Only the simulator's AVPlayer stand-in names this: it can't open MKV or decode HEVC and Dolby Vision.
        if case .unsupportedFormat? = error as? PlaybackError {
            return "The simulator can't play this stream's format. Play it on an Apple TV."
        }
        return "This stream couldn't be played."
    }
}

extension PlayerModel: NowPlayingCommands {}
