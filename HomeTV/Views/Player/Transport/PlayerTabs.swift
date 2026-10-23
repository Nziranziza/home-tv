import SwiftUI

/// The Info and Continue Watching tabs under the track.
struct PlayerTabs: View {
    let focus: FocusState<PlayerFocus?>.Binding
    let onSelect: (PlayerFocus) -> Void

    var body: some View {
        HStack(spacing: 24) {
            PlayerTab(title: "Info") { onSelect(.info) }
                .focused(focus, equals: .info)
            PlayerTab(title: "Continue Watching") { onSelect(.continueWatching) }
                .focused(focus, equals: .continueWatching)
        }
        .focusSection()
    }
}
