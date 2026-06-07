import SwiftUI

// MARK: - Segmented control

/// A frosted segmented control: a rounded `.ultraThinMaterial` track with a muted leading label
/// and pill segments. The selected segment shows a white thumb; the focused segment shows the
/// brightest thumb with a lift — embracing the tvOS focus highlight. A plain `HStack` of buttons
/// (no `ScrollView`/`focusSection`) so left/right traverse the segments natively.
struct SegmentedControl: View {
    let label: String
    let options: [String]
    let selected: String
    var focus: FocusState<StreamPickerView.PickerFocus?>.Binding
    let focusCase: (String) -> StreamPickerView.PickerFocus
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 18) {
            Text(label.uppercased())
                .font(.system(size: 15, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(Theme.Color.tertiaryText)
                .frame(width: 96, alignment: .leading)

            // Generous spacing so a focused segment's 1.05 lift doesn't visually touch its
            // neighbour.
            HStack(spacing: 12) {
                ForEach(options, id: \.self) { option in
                    Button { onSelect(option) } label: {
                        Text(option).fixedSize()
                    }
                    .buttonStyle(SegmentStyle(isSelected: selected == option))
                    .focused(focus, equals: focusCase(option))
                }
            }
            .padding(6)
            .background(
                Capsule(style: .continuous).fill(.ultraThinMaterial)
            )
            .overlay(
                Capsule(style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1)
            )
        }
    }
}

struct SegmentStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, isSelected: isSelected)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let isSelected: Bool
        @Environment(\.isFocused) private var isFocused

        private var thumbOpacity: Double {
            if isFocused { return 1.0 }
            return isSelected ? 0.92 : 0.0
        }

        private var foreground: Color {
            (isFocused || isSelected) ? .black : Theme.Color.secondaryText
        }

        var body: some View {
            configuration.label
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(foreground)
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(Capsule(style: .continuous).fill(Color.white.opacity(thumbOpacity)))
                .scaleEffect(configuration.isPressed ? 0.96 : (isFocused ? 1.05 : 1.0))
                .shadow(color: .black.opacity(isFocused ? 0.3 : 0.0), radius: 10, y: 4)
                .animation(.easeOut(duration: 0.18), value: isFocused)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}
