import SwiftUI

/// `Subtitles will look like this.`, drawn in the active caption style while the Style menu is open.
struct SubtitleStylePreview: View {
    let appearance: CaptionAppearance

    /// The system player's preview size at 100%; the style scales it.
    private static let baseSize: CGFloat = 45

    var body: some View {
        let shadow = CaptionEdgeShadow(edge: appearance.edge)
        Text("Subtitles will look like this.")
            .font(.system(size: Self.baseSize * appearance.relativeSize))
            .foregroundStyle(appearance.foreground)
            .padding(.horizontal, 8)
            .background(appearance.background)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(appearance.window, in: .rect(cornerRadius: appearance.windowCornerRadius))
            .shadow(color: shadow.color, radius: shadow.radius, x: shadow.offset.width, y: shadow.offset.height)
            .shadow(color: shadow.outlineColor, radius: 1)
            .shadow(color: shadow.outlineColor, radius: 1)
    }
}
