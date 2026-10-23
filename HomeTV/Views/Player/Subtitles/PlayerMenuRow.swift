import SwiftUI

/// A menu row: a checkmark for the current choice, a title with an optional grey value under it, and a
/// trailing chevron or gear. Focused, it's a white capsule with dark text.
struct PlayerMenuRow: View {
    let title: String
    var value: String?
    var isChecked = false
    var accessory: PlayerMenuAccessory = .none
    let action: () -> Void

    static var height: CGFloat { 66 }
    static var heightWithValue: CGFloat { 86 }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 23) {
                Image(systemName: "checkmark")
                    .frame(width: 21)
                    .opacity(isChecked ? 1 : 0)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                    if let value {
                        Text(value)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                PlayerMenuRowAccessory(accessory: accessory)
            }
            .font(.caption)
            .padding(.leading, 30)
            .frame(height: value == nil ? Self.height : Self.heightWithValue)
        }
        .buttonStyle(PlayerMenuRowStyle())
        .accessibilityAddTraits(isChecked ? .isSelected : [])
    }
}
