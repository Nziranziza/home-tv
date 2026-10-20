/// Where the in-app player is, independent of the engine.
enum PlaybackState: Equatable, Sendable {
    case idle
    case loading
    case buffering
    case playing
    case paused
    case ended
    case failed
}
