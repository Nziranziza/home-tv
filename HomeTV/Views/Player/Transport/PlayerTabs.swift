import SwiftUI

/// The Info and Continue Watching tabs under the track, or above the open panel.
struct PlayerTabs: View {
    let focus: FocusState<PlayerFocus?>.Binding
    let panel: PlayerPanel?
    /// Continue Watching is left out when nothing else is in progress.
    let showsContinueWatching: Bool
    let onSelect: (PlayerFocus) -> Void
    /// Up from a tab while a panel is up, with nothing above to move to.
    let onExitUp: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            PlayerTab(title: "Info", isHighlighted: panel == .info) { onSelect(.info) }
                .focused(focus, equals: .info)
                .onMoveCommand(perform: exitUp)
            if showsContinueWatching {
                PlayerTab(title: "Continue Watching", isHighlighted: panel == .continueWatching) {
                    onSelect(.continueWatching)
                }
                .focused(focus, equals: .continueWatching)
                .onMoveCommand(perform: exitUp)
            }
        }
        .focusSection()
    }

    // Fires only where focus can't move, so with the track above it never does.
    private func exitUp(_ direction: MoveCommandDirection) {
        if direction == .up { onExitUp() }
    }
}
