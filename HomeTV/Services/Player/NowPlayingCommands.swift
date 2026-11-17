import Foundation

/// What Siri and Control Center can ask the player to do.
@MainActor
protocol NowPlayingCommands: AnyObject {
    func play()
    func pause()
    func togglePlayPause()
    func skip(by seconds: TimeInterval)
    func seek(to time: TimeInterval)
    /// A held seek from Control Center or another remote: scans like a held Left/Right.
    func beginScan(_ direction: PlayerScan.Direction)
    func endScan()
}
