import SwiftUI

/// A round transport button: dark glass at rest, white with a dark glyph when focused.
struct PlayerRoundButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    private static let diameter: CGFloat = 70

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.body)
                .frame(width: Self.diameter, height: Self.diameter)
        }
        .buttonStyle(.playerRound)
    }
}
