import Foundation
import MediaPlayer

/// Publishes the in-app player to `MPNowPlayingInfoCenter` and routes `MPRemoteCommandCenter` back to it,
/// for Siri and Control Center.
@MainActor
final class NowPlayingController {
    private var title = ""
    private var targets: [(MPRemoteCommand, Any)] = []

    func activate(title: String, commands: some NowPlayingCommands) {
        self.title = title
        let center = MPRemoteCommandCenter.shared()
        let skip = PlayerModel.skipInterval
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: skip)]
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: skip)]
        // Remote command handlers run on the main thread.
        add(center.playCommand) { [weak commands] _ in commands?.play() }
        add(center.pauseCommand) { [weak commands] _ in commands?.pause() }
        add(center.togglePlayPauseCommand) { [weak commands] _ in commands?.togglePlayPause() }
        add(center.skipForwardCommand) { [weak commands] _ in commands?.skip(by: skip) }
        add(center.skipBackwardCommand) { [weak commands] _ in commands?.skip(by: -skip) }
        add(center.changePlaybackPositionCommand) { [weak commands] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return }
            commands?.seek(to: event.positionTime)
        }
        update(elapsed: 0, duration: 0, isPlaying: false)
    }

    func update(elapsed: TimeInterval, duration: TimeInterval, isPlaying: Bool) {
        guard !targets.isEmpty else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
        ]
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        center.playbackState = isPlaying ? .playing : .paused
    }

    func deactivate() {
        for (command, target) in targets {
            command.removeTarget(target)
        }
        targets.removeAll()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    private func add(_ command: MPRemoteCommand, _ handle: @escaping @MainActor (MPRemoteCommandEvent) -> Void) {
        let target = command.addTarget { event in
            MainActor.assumeIsolated { handle(event) }
            return .success
        }
        command.isEnabled = true
        targets.append((command, target))
    }
}
