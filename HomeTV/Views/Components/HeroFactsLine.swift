import SwiftUI

/// The hero's facts line: `year · runtime` for a title, `air date · run time` for an episode, followed
/// by the quality badges (PLACEHOLDER quality until addons provide them).
///
/// Shared by the title detail hero and the episode hero so the two read identically — each previously
/// carried its own copy of this row, and the detail's copy had drifted to a hardcoded font that only
/// happened to equal `Theme.Hero.chipFont`.
struct HeroFactsLine: View {
    let text: String

    var body: some View {
        HStack(spacing: Theme.Hero.metaChipsSpacing) {
            Text(text)
                .font(Theme.Hero.chipFont)
                .foregroundStyle(Theme.Color.primaryText)
            QualityBadges()
        }
    }
}
