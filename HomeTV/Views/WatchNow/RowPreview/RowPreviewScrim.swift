import SwiftUI

/// Darkens the card's bottom and left under the metadata, so text reads on bright art or video.
struct RowPreviewScrim: View {
    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0), location: 0.35),
                    .init(color: .black.opacity(0.75), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.5), location: 0),
                    .init(color: .black.opacity(0), location: 0.6)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}
