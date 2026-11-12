import SwiftUI

/// The Info panel's poster tile.
struct PlayerInfoPoster: View {
    let url: URL?

    static let size = CGSize(width: 136, height: 204)
    /// Concentric with the panel.
    private static let cornerRadius = PlayerInfoPanel.cornerRadius - PlayerInfoPanel.inset

    var body: some View {
        RemoteImage(url: url, targetSize: Self.size) {
            Color.white.opacity(0.08)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(.rect(cornerRadius: Self.cornerRadius))
    }
}
