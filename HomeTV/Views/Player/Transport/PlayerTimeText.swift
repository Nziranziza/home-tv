import SwiftUI

/// The transport bar's elapsed or remaining time.
struct PlayerTimeText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .bold()
            .monospacedDigit()
            .foregroundStyle(.white)
            // Digits change in place; a skip glides the label, not the text.
            .contentTransition(.identity)
    }
}
