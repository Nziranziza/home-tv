import AVFoundation
import Observation

/// Drives a single inline hero trailer: owns the `AVPlayer`, loops it, falls through to the next
/// source when one fails (Trailerio's IMDb URLs are signed/expiring), and exposes `isReady` — the one
/// bit of state the SwiftUI hero observes to crossfade the video in over the still backdrop. Playback
/// is unmuted (Apple TV trailers aren't muted, and there is no mute control, matching the TV app).
///
/// This is the app's first in-app player. One controller per visible hero; it always tears down on
/// disappear, and the shared `.playback` audio session + `audioOwner` handoff keep only one surface
/// audible at a time.
@MainActor
@Observable
final class TrailerPlaybackController {
    /// The player backing the hero video layer. nil until a candidate is loaded.
    private(set) var player: AVPlayer?
    /// Flips true once playback actually produces frames — the hero crossfades the video in only then,
    /// so a failed/stalled source never replaces the still backdrop.
    private(set) var isReady = false
    /// Loop the trailer (the detail hero). The Watch Now carousel sets this false and uses
    /// `onPlaybackEnded` to page to the next featured title instead of replaying.
    var loops = true
    /// Called when a non-looping trailer reaches its end.
    var onPlaybackEnded: (() -> Void)?

    /// The controller that currently owns audio. A pushed detail hero plays over a still-alive Watch Now
    /// hero (a NavigationStack push doesn't disappear the root), so without this both would play sound at
    /// once. Whoever calls `play()` last pauses the previous owner; the paused one stays put (its loop
    /// can't advance while paused) until its own surface reappears and replays.
    @MainActor private static weak var audioOwner: TrailerPlaybackController?

    private var candidates: [TrailerCandidate] = []
    private var candidateIndex = 0
    /// Identity of the loaded list, so re-`load`ing the same candidates is a no-op (an unrelated state
    /// change re-running the loader must not restart the trailer).
    private var loadedKey: String?
    /// Whether we want the player running (survives a candidate fall-through).
    private var wantsPlayback = false

    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var notificationTokens: [any NSObjectProtocol] = []
    private var fallbackTask: Task<Void, Never>?
    private var autoplayTask: Task<Void, Never>?

    // MARK: - Loading

    /// Point the controller at a title's ordered trailer sources. No-op if the same list is already
    /// loaded. Does not start playback — call `autoplay(after:)` or `play()`.
    func load(_ newCandidates: [TrailerCandidate]) {
        let key = newCandidates.map(\.id).joined(separator: "|")
        guard key != loadedKey else { return }
        teardown()
        loadedKey = key
        candidates = newCandidates
        candidateIndex = 0
        guard !candidates.isEmpty else { return }
        startCurrentCandidate()
    }

    /// Apple-TV behavior: let the still backdrop sit, then begin the trailer after a short beat.
    func autoplay(after delay: Duration = .seconds(1.2)) {
        autoplayTask?.cancel()
        autoplayTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.play()
        }
    }

    func play() {
        wantsPlayback = true
        if TrailerPlaybackController.audioOwner !== self {
            TrailerPlaybackController.audioOwner?.pause()
            TrailerPlaybackController.audioOwner = self
        }
        player?.play()
    }

    func pause() {
        wantsPlayback = false
        autoplayTask?.cancel()
        player?.pause()
    }

    /// Stop everything and release the player. Called on disappear and before loading a new title.
    func teardown() {
        autoplayTask?.cancel(); autoplayTask = nil
        tearDownPlayerOnly()
        // Clear the play intent too, so a subsequent load(_:) doesn't auto-start before its caller
        // explicitly asks (the contract is: loading alone never begins playback).
        wantsPlayback = false
        loadedKey = nil
        candidates = []
        candidateIndex = 0
    }

    // MARK: - Playback setup

    private func startCurrentCandidate() {
        guard candidates.indices.contains(candidateIndex) else { return }
        configureAudioSession()

        let item = AVPlayerItem(url: candidates[candidateIndex].url)
        let player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .none   // we loop by seeking to zero
        self.player = player

        addReadinessObserver(to: player)
        observeStatus(of: item)
        observeLoop(of: item)
        observeFailure(of: item)
        startFallbackTimer()

        if wantsPlayback { player.play() }
    }

    /// Item-level status: a load failure (e.g. a 403 on a signed/HLS source) flips to `.failed` without
    /// ever playing, so it would never fire `failedToPlayToEndTime` — observe it here to fall through to
    /// the next source immediately instead of waiting out the fallback timer.
    private func observeStatus(of item: AVPlayerItem) {
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status   // Sendable enum read synchronously off the KVO thread
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch status {
                case .failed: self.advanceToNextCandidate()
                case .readyToPlay: if self.wantsPlayback { self.player?.play() }
                default: break
                }
            }
        }
    }

    /// The first frame with a positive time means the video is actually on screen — the moment to
    /// crossfade it in over the still. `.main` queue callback, so `assumeIsolated` is safe.
    private func addReadinessObserver(to player: AVPlayer) {
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, time.seconds > 0, !self.isReady else { return }
                self.isReady = true
                // Readiness is a one-shot signal — stop the 10 Hz callback once it's fired.
                if let observer = self.timeObserver {
                    self.player?.removeTimeObserver(observer)
                    self.timeObserver = nil
                }
            }
        }
    }

    /// End-of-item: loop by seeking to zero, or (Watch Now) hand off to `onPlaybackEnded` to page on.
    /// `.main` queue callback, so `assumeIsolated` is safe.
    private func observeLoop(of item: AVPlayerItem) {
        let token = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let player = self.player else { return }
                if self.loops {
                    player.seek(to: .zero)
                    if self.wantsPlayback { player.play() }
                } else {
                    self.onPlaybackEnded?()
                }
            }
        }
        notificationTokens.append(token)
    }

    /// A failed source falls through to the next candidate.
    private func observeFailure(of item: AVPlayerItem) {
        let token = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.advanceToNextCandidate()
            }
        }
        notificationTokens.append(token)
    }

    /// If a source never reaches the screen within the window, treat it as dead and try the next.
    private func startFallbackTimer() {
        fallbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, let self, !self.isReady else { return }
            self.advanceToNextCandidate()
        }
    }

    /// Move to the next trailer source, keeping the loaded title and the play intent. Gives up
    /// (leaving the still backdrop) once sources are exhausted.
    private func advanceToNextCandidate() {
        candidateIndex += 1
        guard candidates.indices.contains(candidateIndex) else {
            // No more sources — release the dead player + its observers, leaving the still backdrop.
            tearDownPlayerOnly()
            return
        }
        tearDownPlayerOnly()
        startCurrentCandidate()
    }

    /// Release the current player + its observers without forgetting which title is loaded.
    private func tearDownPlayerOnly() {
        fallbackTask?.cancel(); fallbackTask = nil
        statusObservation?.invalidate(); statusObservation = nil
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
        notificationTokens = []
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        player?.pause()
        player = nil
        isReady = false
    }

    private static var audioConfigured = false

    /// Set the playback category once per app session — re-activating it on every candidate caused
    /// needless work (and can hitch). The category persists, so once is enough.
    private func configureAudioSession() {
        guard !TrailerPlaybackController.audioConfigured else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
            // Mark configured only after both calls succeed, so a failure leaves it retryable.
            TrailerPlaybackController.audioConfigured = true
        } catch {
            // Leave audioConfigured false — a later candidate will retry.
        }
    }
}
