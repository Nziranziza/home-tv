import Observation

/// The entry the detail panel describes: the last one focused. Kept apart from the list so a focus move
/// redraws only the panel.
@Observable
@MainActor
final class PlayerTestSelection {
    var entry: PlayerTestEntry?
}
