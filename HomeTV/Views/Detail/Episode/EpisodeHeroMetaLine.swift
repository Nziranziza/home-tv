import SwiftUI

/// The episode hero's facts line: air date · run time, followed by the quality badges (PLACEHOLDER
/// quality until addons provide them).
struct EpisodeHeroMetaLine: View {
    let factsLine: String

    var body: some View {
        HStack(spacing: 14) {
            Text(factsLine)
                .font(Theme.Hero.chipFont)
                .foregroundStyle(Theme.Color.primaryText)
            QualityBadges()
        }
    }
}
