/// Failures an engine can name, so the player can say more than "couldn't be played".
enum PlaybackError: Error {
    /// The engine can't open or decode this container or codec.
    case unsupportedFormat
}
