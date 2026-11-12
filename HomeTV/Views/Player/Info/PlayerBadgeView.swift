import SwiftUI

/// A quality badge: 4K filled white, the rest outlined.
struct PlayerBadgeView: View {
    let badge: PlayerBadge

    /// Badges are glyph-sized, below the smallest text style, so they scale from caption2.
    @ScaledMetric(relativeTo: .caption2) private var fontSize: CGFloat = 15

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        Text(badge.title)
            .font(.system(size: fontSize, weight: .bold))
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .foregroundStyle(badge == .fourK ? .black : .white)
            .background {
                if badge == .fourK {
                    shape.fill(.white)
                } else {
                    shape.strokeBorder(.white, lineWidth: 1.5)
                }
            }
    }
}
