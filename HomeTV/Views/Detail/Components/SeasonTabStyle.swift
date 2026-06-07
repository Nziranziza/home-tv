import SwiftUI

// MARK: - Season selector tab

struct SeasonTabStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, isSelected: isSelected)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let isSelected: Bool
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .foregroundStyle(foreground)
                .background(
                    Capsule(style: .continuous).fill(fill)
                )
                .scaleEffect(configuration.isPressed ? 0.97 : (isFocused ? 1.05 : 1.0))
                .animation(.easeOut(duration: 0.18), value: isFocused)
        }

        private var foreground: Color {
            if isFocused { return .black }
            return isSelected ? Theme.Color.primaryText : Theme.Color.tertiaryText
        }

        private var fill: Color {
            if isFocused { return Theme.Color.primaryText }
            return isSelected ? Theme.Color.primaryText.opacity(0.18) : .clear
        }
    }
}

