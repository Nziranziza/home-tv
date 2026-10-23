import SwiftUI

/// A capsule tab under the track.
struct PlayerTab: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body)
                .padding(.horizontal, 30)
                .padding(.vertical, 14.5)
        }
        .buttonStyle(.playerTab)
    }
}
