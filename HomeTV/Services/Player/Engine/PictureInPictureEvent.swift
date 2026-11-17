/// Picture in Picture's progress, reported by the engine to `PlayerModel`.
enum PictureInPictureEvent {
    /// The video is in the corner.
    case started
    /// The viewer expanded it. `completion` runs once the player is back on screen.
    case restore(completion: (Bool) -> Void)
    /// The corner closed, after a restore or by the viewer.
    case stopped
}
