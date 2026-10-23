import Foundation
import Observation
import UIKit

/// Owns the playback engine for one `PlayerScreen`. Views read this, never the engine.
@Observable
@MainActor
final class PlayerModel {
    let request: PlayerRequest
    @ObservationIgnored private let engine: any PlaybackEngine
    /// Set when the stream can't play, for the screen to show.
    private(set) var errorMessage: String?
    /// Set when playback reached its end, so the screen can close.
    private(set) var didFinish = false
    @ObservationIgnored private var isStarted = false

    init(request: PlayerRequest, engine: (any PlaybackEngine)? = nil) {
        self.request = request
        self.engine = engine ?? PlaybackEngines.make()
    }

    var state: PlaybackState { engine.state }
    var videoView: UIView { engine.videoView }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        PlaybackAudioSession.configure()
        engine.onFinish = { [weak self] error in
            guard let self else { return }
            if error == nil {
                didFinish = true
            } else {
                errorMessage = Self.message(for: error)
            }
        }
        engine.load(url: request.url, headers: request.headers, startTime: request.startTime)
    }

    /// The remote's Play/Pause button.
    func togglePlayPause() {
        switch engine.state {
        case .paused: engine.play()
        case .playing, .buffering: engine.pause()
        default: break
        }
    }

    func stop() {
        engine.stop()
    }

    nonisolated static func message(for error: (any Error)?) -> String {
        // Only the simulator's AVPlayer stand-in names this: it can't open MKV or decode HEVC and Dolby Vision.
        if case .unsupportedFormat? = error as? PlaybackError {
            return "The simulator can't play this stream's format. Play it on an Apple TV."
        }
        return "This stream couldn't be played."
    }
}
