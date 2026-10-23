import SwiftUI

/// The body of `PlayerGlassButtonStyle`, a view so it can read the focus environment.
struct PlayerGlassButton<S: Shape>: View {
    let configuration: ButtonStyleConfiguration
    let shape: S
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .foregroundStyle(isFocused ? .black : .white)
            .background {
                if isFocused {
                    shape.fill(.white)
                        .shadow(color: .black.opacity(0.35), radius: 12, y: 8)
                } else {
                    Color.clear.glassEffect(.regular, in: shape)
                }
            }
            .scaleEffect(isFocused ? (configuration.isPressed ? 1.08 : 1.14) : 1)
            .animation(.easeOut(duration: 0.12), value: isFocused)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
