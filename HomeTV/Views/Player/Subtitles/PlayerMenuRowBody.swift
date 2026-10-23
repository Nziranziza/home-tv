import SwiftUI

/// The body of `PlayerMenuRowStyle`, a view so it can read the focus environment.
struct PlayerMenuRowBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .foregroundStyle(isFocused ? .black : .white)
            .background {
                if isFocused {
                    // A little taller than the row, as the system player draws it.
                    Capsule()
                        .fill(.white)
                        .padding(.vertical, -3.5)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: isFocused)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
