import SwiftUI

/// The next episode's still, full screen behind the corner video, darkened at the lower left for the
/// details over it.
struct UpNextBackdrop: View {
    let url: URL?

    private static let size = CGSize(width: 1920, height: 1080)

    var body: some View {
        RemoteImage(url: url, targetSize: Self.size, contentMode: .fill) {
            Color.black
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay {
            LinearGradient(
                colors: [.black.opacity(0.7), .clear],
                startPoint: .bottomLeading,
                endPoint: .center
            )
        }
    }
}
