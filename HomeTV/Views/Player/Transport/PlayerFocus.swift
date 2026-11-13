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
    /// A Continue Watching card, by its item's id.
    case continueWatchingCard(String)

    /// The panel this target keeps up: a tab and its panel's controls.
    var panel: PlayerPanel? {
        switch self {
        case .info, .fromBeginning, .goToDetail: .info
        case .continueWatching, .continueWatchingCard: .continueWatching
        default: nil
        }
    }
}
