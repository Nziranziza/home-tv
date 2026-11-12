import SwiftUI

/// A capsule button on the Info panel.
struct PlayerInfoButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.body)
                .frame(width: PlayerInfoButtons.size.width, height: PlayerInfoButtons.size.height)
        }
        .buttonStyle(.playerTab)
    }
}
