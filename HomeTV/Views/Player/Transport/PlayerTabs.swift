import SwiftUI

/// The Info and Continue Watching tabs under the track, or above the Info panel.
struct PlayerTabs: View {
    let focus: FocusState<PlayerFocus?>.Binding
    let isInfoOpen: Bool
    let onSelect: (PlayerFocus) -> Void
    /// Up from a tab while the panel is up, with nothing above to move to.
    let onExitUp: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            PlayerTab(title: "Info", isHighlighted: isInfoOpen) { onSelect(.info) }
                .focused(focus, equals: .info)
                .onMoveCommand(perform: exitUp)
            PlayerTab(title: "Continue Watching") { onSelect(.continueWatching) }
                .focused(focus, equals: .continueWatching)
                .onMoveCommand(perform: exitUp)
        }
        .focusSection()
    }

    // Fires only where focus can't move, so with the track above it never does.
    private func exitUp(_ direction: MoveCommandDirection) {
        if direction == .up { onExitUp() }
    }
}
