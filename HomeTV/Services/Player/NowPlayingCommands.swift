import Foundation

/// What Siri and Control Center can ask the player to do.
@MainActor
protocol NowPlayingCommands: AnyObject {
    func play()
    func pause()
    func togglePlayPause()
    func skip(by seconds: TimeInterval)
    func seek(to time: TimeInterval)
}
