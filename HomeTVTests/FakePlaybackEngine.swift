import Foundation
import UIKit
@testable import HomeTV

/// A scriptable engine for the player's model tests.
@MainActor
final class FakePlaybackEngine: PlaybackEngine {
    let videoView = UIView()
    var state: PlaybackState = .playing
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var subtitleDelay: TimeInterval = 0
    var externalSubtitles: [ExternalSubtitle] = []
    var videoFormat: VideoFormat?
    var onFinish: ((Error?) -> Void)?
    var onTracksReady: (() -> Void)?
    var audioPicker: (@Sendable ([PlaybackTrack]) -> PlaybackTrack?)?
    var audioTracks: [PlaybackTrack] = []
    /// Every audio or video selection.
    private(set) var selections: [PlaybackTrack] = []
    var subtitleTracks: [PlaybackTrack] = []
    /// Every subtitle selection, nil for off.
    private(set) var subtitleSelections: [PlaybackTrack?] = []
    private(set) var seeks: [TimeInterval] = []
    /// False leaves the clock behind, like an engine still seeking.
    var seekLands = true
    var isSeeking: Bool { !seekLands && !seeks.isEmpty }

    private(set) var prepares: [URL] = []
    private(set) var loads: [URL] = []

    func prepare(url: URL, headers: [String: String], startTime: TimeInterval) { prepares.append(url) }
    func load(url: URL, headers: [String: String], startTime: TimeInterval) { loads.append(url) }
    func play() { state = .playing }
    func pause() { state = .paused }

    func seek(to time: TimeInterval) {
        seeks.append(time)
        if seekLands { currentTime = time }
    }

    func tracks(of kind: PlaybackTrack.Kind) -> [PlaybackTrack] {
        switch kind {
        case .audio: audioTracks
        case .subtitle: subtitleTracks + externalSubtitles.enumerated().map { $1.track(at: $0, isSelected: false) }
        case .video: []
        }
    }

    func select(_ track: PlaybackTrack) { selections.append(track) }
    func selectSubtitle(_ track: PlaybackTrack?) { subtitleSelections.append(track) }
    private(set) var isStopped = false
    func stop() { isStopped = true }
}
