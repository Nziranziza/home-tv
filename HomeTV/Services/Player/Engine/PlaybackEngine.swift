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
    /// Called once when playback ends, with the error if it failed.
    var onFinish: ((Error?) -> Void)? { get set }
    /// Called each time the stream's tracks become known, including after a decoder restart.
    var onTracksReady: (() -> Void)? { get set }
    /// Picks the audio track a stream opens with. May be called off the main actor.
    var audioPicker: (@Sendable ([PlaybackTrack]) -> PlaybackTrack?)? { get set }

    /// Opens and buffers the stream ahead of Select, without playing it or switching the TV's mode.
    func prepare(url: URL, headers: [String: String], startTime: TimeInterval)
    /// Starts playback. Starts from the buffer when `prepare` opened the same stream.
    func load(url: URL, headers: [String: String], startTime: TimeInterval)
    func play()
    func pause()
    func seek(to time: TimeInterval)
    func tracks(of kind: PlaybackTrack.Kind) -> [PlaybackTrack]
    func select(_ track: PlaybackTrack)
    /// Shows `track`'s subtitles, or none for nil.
    func selectSubtitle(_ track: PlaybackTrack?)
    /// Stops playback and releases the decoder. The engine can't be reused.
    func stop()
}
