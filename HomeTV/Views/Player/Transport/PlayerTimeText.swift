import SwiftUI

/// The transport bar's elapsed or remaining time.
struct PlayerTimeText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .bold()
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }
}
