import SwiftUI

/// A capsule tab under the track. Highlighted while its panel is up.
struct PlayerTab: View {
    let title: String
    var isHighlighted = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body)
                .padding(.horizontal, 30)
                .padding(.vertical, 14.5)
        }
        .buttonStyle(.playerTab(isHighlighted: isHighlighted))
    }
}
