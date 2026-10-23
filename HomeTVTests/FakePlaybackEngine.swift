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
    var onFinish: ((Error?) -> Void)?
    var onTracksReady: (() -> Void)?
    var audioTracks: [PlaybackTrack] = []
    var subtitleTracks: [PlaybackTrack] = []
    /// Every subtitle selection, nil for off.
    private(set) var subtitleSelections: [PlaybackTrack?] = []
    private(set) var seeks: [TimeInterval] = []
    /// False leaves the clock behind, like an engine still seeking.
    var seekLands = true
    var isSeeking: Bool { !seekLands && !seeks.isEmpty }

    func load(url: URL, headers: [String: String], startTime: TimeInterval) {}
    func play() { state = .playing }
    func pause() { state = .paused }

    func seek(to time: TimeInterval) {
        seeks.append(time)
        if seekLands { currentTime = time }
    }

    func tracks(of kind: PlaybackTrack.Kind) -> [PlaybackTrack] {
        switch kind {
        case .audio: audioTracks
        case .subtitle: subtitleTracks
        case .video: []
        }
    }

    func select(_ track: PlaybackTrack) {}
    func selectSubtitle(_ track: PlaybackTrack?) { subtitleSelections.append(track) }
    func stop() {}
}
