import SwiftUI

/// The episode hero's title block: the muted show name above the large episode title. Episodes have no
/// logo art (unlike the show hero), so this is always text.
struct EpisodeHeroTitle: View {
    let showName: String
    let episodeTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(showName)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Theme.Color.primaryText.opacity(0.6))
                .lineLimit(1)
            Text(episodeTitle)
                .font(.system(size: 52, weight: .bold))
                .foregroundStyle(Theme.Color.primaryText)
                .lineLimit(2)
        }
        .frame(maxWidth: Theme.Hero.titleMaxWidth, alignment: .leading)
    }
}
