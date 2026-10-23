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
    /// Saves a position (seconds) and runtime (seconds) for the request's item.
    @ObservationIgnored private let recordProgress: @MainActor (Int, Int, PlaybackItem) -> Void
    /// Set once the engine has played, so a stream that never started can't overwrite the resume point.
    @ObservationIgnored private var hasPlayed = false
    @ObservationIgnored private var lastSavedPosition: Int?

    init(
        request: PlayerRequest,
        engine: (any PlaybackEngine)? = nil,
        bar: PlayerBarController? = nil,
        publishesNowPlaying: Bool = true,
        recordProgress: (@MainActor (Int, Int, PlaybackItem) -> Void)? = nil
    ) {
        self.request = request
        self.engine = engine ?? PlaybackEngines.make()
        self.bar = bar ?? PlayerBarController()
        nowPlaying = publishesNowPlaying ? NowPlayingController() : nil
        self.recordProgress = recordProgress ?? { position, runtime, item in
            // A 0 only gets through after a seek back to the start.
            PlaybackProgress.record(position: position, runtime: runtime, item: item, isRestart: position == 0)
        }
    }

    var state: PlaybackState { engine.state }
    var videoView: UIView { engine.videoView }
    var currentTime: TimeInterval { engine.currentTime }
    var duration: TimeInterval { engine.duration }
    var isPlaying: Bool { engine.state == .playing || engine.state == .buffering }
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

    func start() {
        guard !isStarted else { return }
        isStarted = true
        PlaybackAudioSession.configure()
        engine.onFinish = { [weak self] error in
            guard let self else { return }
            if error == nil {
                saveProgress(atEnd: true)
                didFinish = true
            } else {
                errorMessage = Self.message(for: error)
            }
        }
        engine.load(url: request.url, headers: request.headers, startTime: request.startTime)
        nowPlaying?.activate(title: request.title, commands: self)
    }

    /// Click and Play/Pause: toggles playback, or plays from the scrub position, and shows the bar.
    func togglePlayPause() {
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

    /// Menu: hides the bar, dropping any scrub. Returns false when the bar was already hidden, so the
    /// screen closes.
    func handleExit() -> Bool {
        guard bar.isVisible else { return false }
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
        if engine.state == .paused { saveProgress() }
        if isPlaying {
            bar.noteActivity(isPlaying: true)
        } else if engine.state == .paused {
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
        // A seek still in flight, however slow, is where the user is.
        let time = engine.isSeeking ? lastSeek?.time ?? playheadTime : playheadTime
        let position = atEnd ? runtime : Int(time)
        // An unseeked 0 is a clock that hasn't caught up with the start time; after a seek it's a restart.
        guard position > 0 || lastSeek != nil, position != lastSavedPosition else { return }
        lastSavedPosition = position
        PlaybackDiagnostics.log("save \(position)/\(runtime)s \(item.contentID)")
        recordProgress(position, runtime, item)
    }

    func stop() {
        saveProgress()
        nowPlaying?.deactivate()
        bar.hide()
        engine.stop()
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
