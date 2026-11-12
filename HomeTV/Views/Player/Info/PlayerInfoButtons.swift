import SwiftUI

/// From Beginning and Go to Movie / Go to Show, stacked at the Info panel's right.
struct PlayerInfoButtons: View {
    let type: String
    let canGoToDetail: Bool
    let focus: FocusState<PlayerFocus?>.Binding
    let onSelect: (PlayerFocus) -> Void

    static let size = CGSize(width: 360, height: 65)

    var body: some View {
        VStack(spacing: 17) {
            PlayerInfoButton(title: "From Beginning", systemImage: "play.fill") { onSelect(.fromBeginning) }
                .focused(focus, equals: .fromBeginning)
                // The tabs sit at the far left, out of Up's reach, so Up goes back to the Info tab.
                .onMoveCommand { direction in
                    if direction == .up { focus.wrappedValue = .info }
                }
            if canGoToDetail {
                PlayerInfoButton(title: type == "series" ? "Go to Show" : "Go to Movie", systemImage: "info.circle") {
                    onSelect(.goToDetail)
                }
                .focused(focus, equals: .goToDetail)
            }
        }
    }
}
