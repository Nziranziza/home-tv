import SwiftUI

/// The system player's menu panel: dark glass with a grey header over its rows.
struct PlayerMenuPanel<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.leading, 36)
                .padding(.top, 25)
                .padding(.bottom, 13.5)
            content
        }
        .frame(width: PlayerMenuMetrics.width, alignment: .leading)
        .background {
            Color.clear.glassEffect(.regular, in: .rect(cornerRadius: 52))
        }
    }
}
