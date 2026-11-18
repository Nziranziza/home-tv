import Foundation

/// What a sample should do. An item's value overrides its section's.
enum PlayerTestExpectation: String, Codable, Sendable, CaseIterable {
    /// Should play.
    case play
    /// Odd or broken: playing or failing cleanly both pass; hanging or crashing fails.
    case any
    /// Not media: the player should show an error.
    case fail

    var title: String {
        switch self {
        case .play: "Should Play"
        case .any: "Play or Fail Cleanly"
        case .fail: "Should Fail"
        }
    }

    var explanation: String {
        switch self {
        case .play: "A pass is smooth playback with picture and sound in sync."
        case .any: "Playing or showing an error both pass. Hanging or crashing fails."
        case .fail: "Not playable media. A pass is a prompt error message, not a hang."
        }
    }

    var symbol: String {
        switch self {
        case .play: "checkmark.circle.fill"
        case .any: "questionmark.diamond.fill"
        case .fail: "xmark.octagon.fill"
        }
    }
}
