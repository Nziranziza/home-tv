import Foundation
import UIKit

/// The video engine behind the in-app player. Views never touch it; they read `PlayerModel`.
@MainActor
protocol PlaybackEngine: AnyObject {
    /// The surface the engine renders into. Fixed for the engine's lifetime.
    var videoView: UIView { get }
    var state: PlaybackState { get }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    /// True from `seek(to:)` until the engine lands there.
    var isSeeking: Bool { get }
    /// The video track's size and dynamic range, once `onTracksReady` has fired.
    var videoFormat: VideoFormat? { get }
    /// Seconds subtitles are shifted by. Positive shows them later.
    var subtitleDelay: TimeInterval { get set }
    /// Add-on subtitle files, listed by `tracks(of: .subtitle)` after the stream's own; a file is fetched
    /// only once it's selected. Files arriving later are added to the end at any time, so ids don't move.
    var externalSubtitles: [ExternalSubtitle] { get set }
    /// Called once when playback ends, with the error if it failed.
    var onFinish: ((Error?) -> Void)? { get set }
    /// Called each time the stream's tracks become known, including after a decoder restart.
    var onTracksReady: (() -> Void)? { get set }
    /// Picks the audio track a stream opens with. May be called off the main actor.
    var audioPicker: (@Sendable ([PlaybackTrack]) -> PlaybackTrack?)? { get set }
    /// Enhance Dialogue and Reduce Loud Sounds, applied live.
    var audioAdjustments: AudioAdjustments { get set }
    /// Whether the playing audio takes `audioAdjustments`. False for Dolby passthrough and HLS on AVPlayer.
    var canAdjustAudio: Bool { get }

    /// Opens and buffers the stream ahead of Select, without playing it or switching the TV's mode.
    func prepare(url: URL, headers: [String: String], startTime: TimeInterval)
    /// Starts playback. Starts from the buffer when `prepare` opened the same stream.
    func load(url: URL, headers: [String: String], startTime: TimeInterval)
    func play()
    func pause()
    /// Lands on `time` exactly when `isAccurate`, else on a nearby keyframe, which is faster.
    func seek(to time: TimeInterval, isAccurate: Bool)
    func tracks(of kind: PlaybackTrack.Kind) -> [PlaybackTrack]
    func select(_ track: PlaybackTrack)
    /// Shows `track`'s subtitles, or none for nil.
    func selectSubtitle(_ track: PlaybackTrack?)
    /// The file's chapters, once `onTracksReady` has fired; empty when it has none.
    func loadChapters() async -> [PlaybackChapter]
    /// Stops playback and releases the decoder. The engine can't be reused.
    func stop()
}

extension PlaybackEngine {
    func seek(to time: TimeInterval) {
        seek(to: time, isAccurate: false)
    }
}
