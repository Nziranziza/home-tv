/// The player's focus targets. `surface` is the only one while the transport bar is hidden.
enum PlayerFocus: Hashable {
    case surface
    case scrubber
    case subtitles
    case audio
    case pictureInPicture
    case info
    case continueWatching
    case fromBeginning
    case goToDetail

    /// The Info tab and its panel's buttons, which keep the panel up.
    var isInInfo: Bool {
        switch self {
        case .info, .fromBeginning, .goToDetail: true
        default: false
        }
    }
}
