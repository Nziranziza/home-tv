import SwiftUI

/// Stremio-style loading screen: the title's logo, centered and slowly pulsing, while the stream buffers.
/// Falls back to the title's name when there's no logo.
struct PlayerLoadingView: View {
    let title: String
    let logoURL: URL?

    private static let logoSize = CGSize(width: 560, height: 240)

    var body: some View {
        Group {
            if let logoURL {
                RemoteImage(url: logoURL, targetSize: Self.logoSize, contentMode: .fit, trimsTransparency: true) {
                    PlayerLoadingTitle(title: title)
                }
                .accessibilityLabel(title)
            } else {
                PlayerLoadingTitle(title: title)
            }
        }
        .frame(maxWidth: Self.logoSize.width, maxHeight: Self.logoSize.height)
        .phaseAnimator([false, true]) { content, isBright in
            content.opacity(isBright ? 1 : 0.35)
        } animation: { _ in
            .easeInOut(duration: 1.2)
        }
    }
}

#Preview {
    ZStack {
        Color.black
        PlayerLoadingView(title: "Spider-Man: Brand New Day", logoURL: nil)
    }
    .ignoresSafeArea()
}
