import SwiftUI

/// The episode hero's synopsis: the season/episode label bolded ahead of the overview, at the shared
/// hero description styling so it reads identically to the title detail's logline.
struct EpisodeHeroDescription: View {
    let label: String
    let overview: String

    var body: some View {
        (
            Text("\(label):  ")
                .font(Theme.Hero.descriptionFont.weight(.semibold))
            + Text(overview)
                .font(Theme.Hero.descriptionFont)
        )
        .foregroundStyle(.white.opacity(Theme.Hero.descriptionOpacity))
        .lineSpacing(Theme.Hero.descriptionLineSpacing)
        .lineLimit(Theme.Hero.descriptionLineLimit)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: Theme.Hero.descriptionMaxWidth, alignment: .leading)
    }
}
