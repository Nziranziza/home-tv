import SwiftUI

extension View {
    /// Shrinks the full-screen video into Up Next's corner picture. A scale, not a resize, so the engine's
    /// view keeps its size and the move costs no relayout.
    func upNextVideoFrame(isCornered: Bool, isFocused: Bool) -> some View {
        let scale = isCornered ? UpNextLayout.videoScale * (isFocused ? UpNextLayout.focusedGrowth : 1) : 1
        return background(.black)
            // Drawn at full size, so the radius is divided by the scale it will be shown at.
            .clipShape(.rect(cornerRadius: isCornered ? UpNextLayout.videoCornerRadius / scale : 0))
            .scaleEffect(scale, anchor: .topTrailing)
            .offset(
                x: isCornered ? -UpNextLayout.videoInset.width : 0,
                y: isCornered ? UpNextLayout.videoInset.height : 0
            )
            .shadow(color: .black.opacity(isFocused ? 0.6 : 0), radius: 20, y: 10)
    }
}
