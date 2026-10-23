/// The player's focus targets. `surface` is the only one while the transport bar is hidden.
enum PlayerFocus: Hashable {
    case surface
    case scrubber
    case subtitles
    case audio
    case pictureInPicture
    case info
    case continueWatching
}
