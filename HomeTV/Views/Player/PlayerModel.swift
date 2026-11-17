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
    /// The open level of the Subtitles menu, nil while it's closed.
    private(set) var subtitlesMenu: SubtitlesMenuPage?
    private(set) var isAudioMenuOpen = false
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
    /// Where a paused swipe has moved the playhead to; committed on click or Play/Pause.
    private(set) var scrubTime: TimeInterval?
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
        min(max(Double(upNextSecondsLeft) / UpNextTiming.showLead, 0), 1)
    }
    /// Set once the viewer went back to full screen; the next episode still follows at the end.
    @ObservationIgnored private var isUpNextDismissed = false
    /// Set when Next Episode was chosen, so closing doesn't throw away the opened next stream.
    @ObservationIgnored private var rollsOver = false
    @ObservationIgnored private var hasPrewarmedUpNext = false
    @ObservationIgnored private(set) var upNextLoad: Task<Void, Never>?
    @ObservationIgnored private let loadUpNext: @MainActor (PlayerRequest) async throws -> UpNextEpisode?
    /// Failed lookups so far; a failure is retried after `upNextRetryDelay`, up to `UpNextTiming.maxAttempts`.
    @ObservationIgnored private var upNextAttempts = 0
    @ObservationIgnored private let upNextRetryDelay: Duration
    @ObservationIgnored private let prewarmer: PlayerPrewarmer
    @ObservationIgnored private let presenter: PlayerPresenter
    /// True from the video reaching the corner until the corner closes, expanded or not.
    @ObservationIgnored private(set) var isInPictureInPicture = false
    /// Saving, Now Playing and state reactions. Owned here, not by the screen, so they go on in the corner.
    @ObservationIgnored private var sessionTasks: [Task<Void, Never>] = []

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
        presenter: PlayerPresenter? = nil
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
            delays: subtitleDelays
        )
        audio = PlayerAudio(engine: engine, showID: showID, store: audioChoices)
        nowPlaying = publishesNowPlaying ? NowPlayingController() : nil
        self.loadTitleInfo = loadTitleInfo ?? PlayerTitleInfoLoader.load
        self.loadContinueWatching = loadContinueWatching ?? { UserLibrary.continueWatchingItems }
        self.loadUpNext = loadUpNext ?? UpNextLoader.load
        self.upNextRetryDelay = upNextRetryDelay
        self.prewarmer = prewarmer ?? .shared
        self.presenter = presenter ?? .shared
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
    var displayTime: TimeInterval { scrubTime ?? playheadTime }

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
        attachEngine()
        engine.prepare(url: request.url, headers: request.headers, startTime: request.startTime)
    }

    /// A prepared play the viewer moved on from before Select.
    func discard() {
        guard !isStarted else { return }
        engine.stop()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        PlaybackAudioSession.configure()
        if !isPrepared { attachEngine() }
        if let item = request.item {
            titleInfoTask = Task { [weak self, type = request.type, loadTitleInfo] in
                let info = await loadTitleInfo(type, item)
                guard !Task.isCancelled else { return }
                self?.titleInfo = info
            }
        }
        engine.load(url: request.url, headers: request.headers, startTime: request.startTime)
        nowPlaying?.activate(title: request.title, commands: self)
        startSessionTasks()
    }

    private func startSessionTasks() {
        sessionTasks = [
            Task { [weak self] in
                guard var last = self?.state else { return }
                let states = Observations { @MainActor [weak self] in self?.state }
                for await state in states {
                    guard let self, let state else { return }
                    guard state != last else { continue }
                    last = state
                    playbackDidChange()
                }
            },
            Task { [weak self] in
                while (try? await Task.sleep(for: Self.saveInterval)) != nil, let self {
                    saveProgress()
                }
            },
            Task { [weak self] in
                // Keeps Control Center's clock in step; it extrapolates between updates.
                while (try? await Task.sleep(for: .seconds(5))) != nil, let self {
                    publishNowPlaying()
                }
            },
        ]
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
            // The corner has no screen to move on to the next episode or show the error.
            if isInPictureInPicture { presenter.pictureInPictureDidStop(self) }
        }
        engine.onPictureInPicture = { [weak self] event in
            self?.pictureInPictureDidChange(event)
        }
        engine.onTracksReady = { [weak self] in
            guard let self else { return }
            // Audio first: the subtitles' default depends on the audio's language.
            audio.tracksDidLoad()
            subtitles.tracksDidLoad(audioTrack: audio.track)
            badges = PlayerBadge.badges(
                video: engine.videoFormat,
                audio: engine.tracks(of: .audio),
                subtitles: engine.tracks(of: .subtitle)
            )
        }
    }

    /// Click and Play/Pause: toggles playback, or plays from the scrub position, and shows the bar.
    func togglePlayPause() {
        // Up Next holds the screen: play and pause the corner video without the bar.
        if isShowingUpNext, !bar.isVisible {
            if isPlaying { engine.pause() } else if engine.state == .paused { engine.play() }
            return
        }
        if let scrubTime {
            self.scrubTime = nil
            seekEngine(to: scrubTime)
            engine.play()
            bar.show(isPlaying: true)
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

    /// Left/Right: ±10s from the playhead, or from the scrub position while scrubbing.
    func skip(by seconds: TimeInterval) {
        guard canSeek else { return }
        let target = clamped(displayTime + seconds)
        if scrubTime != nil {
            scrubTime = target
        } else {
            seekEngine(to: target)
        }
        bar.show(isPlaying: isPlaying)
    }

    func seek(to time: TimeInterval) {
        guard canSeek else { return }
        scrubTime = nil
        seekEngine(to: clamped(time))
        bar.noteActivity(isPlaying: isPlaying)
    }

    /// A horizontal swipe on the click pad, as a fraction of its width. Scrubs only while paused.
    func scrub(byPadFraction fraction: Double) {
        guard canSeek, engine.state == .paused else { return }
        // A full-width swipe covers a tenth of the title, and never less than a minute.
        let span = max(60, duration / 10)
        scrubTime = clamped(displayTime + fraction * span)
        bar.show(isPlaying: false)
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
        isAudioMenuOpen = true
        bar.hold()
    }

    func closeAudioMenu() {
        isAudioMenuOpen = false
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
        scrubTime = nil
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

    /// Menu: backs out of an open menu one level, else hides the bar, dropping any scrub. Returns false
    /// when the bar was already hidden, so the screen closes.
    func handleExit() -> Bool {
        if isAudioMenuOpen {
            closeAudioMenu()
            return true
        }
        if let page = subtitlesMenu {
            if page == .root { closeSubtitlesMenu() } else { subtitlesMenu = .root }
            return true
        }
        if panel != nil {
            closePanel()
            return true
        }
        guard bar.isVisible else {
            guard isShowingUpNext else { return false }
            dismissUpNext()
            return true
        }
        scrubTime = nil
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
            report(.pause)
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
        sessionTasks.forEach { $0.cancel() }
        sessionTasks = []
        if isInPictureInPicture {
            // Cleared first, so the corner's own stop report is ignored.
            isInPictureInPicture = false
            engine.stopPictureInPicture()
        }
        upNextLoad?.cancel()
        // Accepted, the next screen has already taken the opened stream.
        if hasPrewarmedUpNext, !rollsOver { prewarmer.cancel() }
        pausesOnStart = false
        subtitlesMenu = nil
        isAudioMenuOpen = false
        panel = nil
        titleInfoTask?.cancel()
        resumeTask?.cancel()
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

    // MARK: - Picture in Picture

    /// The Picture in Picture button: the video moves to the corner and the screen closes once it's there.
    func startPictureInPicture() {
        guard errorMessage == nil, state != .failed, state != .ended else { return }
        engine.startPictureInPicture()
    }

    private func pictureInPictureDidChange(_ event: PictureInPictureEvent) {
        switch event {
        case .started:
            isInPictureInPicture = true
            scrubTime = nil
            subtitlesMenu = nil
            isAudioMenuOpen = false
            panel = nil
            bar.hide()
            presenter.enterPictureInPicture(self)
        case .restore(let completion):
            presenter.restorePictureInPicture(self, completion: completion)
        case .stopped:
            guard isInPictureInPicture else { return }
            isInPictureInPicture = false
            presenter.pictureInPictureDidStop(self)
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
        if upNextLoad == nil, UpNextTiming.isResolveDue(remaining: remaining) {
            upNextAttempts += 1
            upNextLoad = Task { [weak self, request, loadUpNext, upNextAttempts, upNextRetryDelay] in
                do {
                    let next = try await loadUpNext(request)
                    guard !Task.isCancelled else { return }
                    self?.upNext = next
                } catch {
                    // A failed request: clearing the lookup lets a later tick try again.
                    guard upNextAttempts < UpNextTiming.maxAttempts,
                          (try? await Task.sleep(for: upNextRetryDelay)) != nil else { return }
                    self?.upNextLoad = nil
                }
            }
        }
        guard let upNext, !isUpNextDismissed, UpNextTiming.isShowDue(remaining: remaining) else {
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

    private func seekEngine(to time: TimeInterval) {
        lastSeek = (time, .now)
        engine.seek(to: time)
        publishNowPlaying()
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
