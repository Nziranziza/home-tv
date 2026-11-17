import SwiftUI

/// The track as the bar's resting focus: Select toggles playback and Left/Right skip. It draws no focus
/// state, like the system player's.
struct PlayerScrubberButton: View {
    let model: PlayerModel
    let focus: FocusState<PlayerFocus?>.Binding
    let onMove: (MoveCommandDirection) -> Void

    /// The time and, during a skip, scan or pause, what the glyph beside it shows.
    private var spokenValue: String {
        let time = PlayerTime.elapsed(model.displayTime)
        guard let indicator = model.timeIndicator else { return time }
        return "\(time), \(indicator.spokenDescription)"
    }

    var body: some View {
        Button(action: model.togglePlayPause) {
            PlayerScrubber(model: model)
        }
        .buttonStyle(PlayerSurfaceButtonStyle())
        .accessibilityValue(spokenValue)
        .focused(focus, equals: .scrubber)
        // On the button itself: Up and Down still move focus to the buttons and tabs.
        .onMoveCommand(perform: onMove)
    }
}
