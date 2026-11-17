import Foundation

/// The glyph beside the elapsed time: a skip, a scan and its level, loading, or paused.
enum PlayerTimeIndicator: Equatable {
    case skip(PlayerScan.Direction)
    /// Buffering after playback began, on the side of the skip that caused it.
    case loading(PlayerScan.Direction)
    case scan(PlayerScan)
    case paused

    /// Backward glyphs sit before the time, the rest after it.
    var isLeading: Bool {
        switch self {
        case .skip(let direction), .loading(let direction): direction == .backward
        case .scan(let scan): scan.direction == .backward
        case .paused: false
        }
    }

    /// What VoiceOver says for the glyph, which itself is hidden.
    var spokenDescription: String {
        switch self {
        case .skip(.backward): String(localized: "Skipped back 10 seconds")
        case .skip(.forward): String(localized: "Skipped forward 10 seconds")
        case .scan(let scan) where scan.direction == .forward: String(localized: "Fast-forward, speed \(scan.level)")
        case .scan(let scan): String(localized: "Rewind, speed \(scan.level)")
        case .loading: String(localized: "Loading")
        case .paused: String(localized: "Paused")
        }
    }
}
