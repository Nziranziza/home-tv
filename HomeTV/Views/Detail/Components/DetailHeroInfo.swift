import SwiftUI

/// The title hero's text block: logo, type/genre chips with the certification box, synopsis (the
/// up-next episode's once a show is under way), and the facts line. Shared by the detail hero and the
/// row preview so both read identically.
struct DetailHeroInfo: View {
    let model: MetaDetailModel

    /// The logo box, in Apple TV's proportions (wide wordmarks reach ≈440 pt, tall ones ≈135 pt).
    static let logoSize = CGSize(width: 440, height: 135)

    var body: some View {
        HeroTitleArt(
            logoURL: model.vm.displayLogoURL,
            accessibilityName: model.meta?.name ?? model.fallbackTitle,
            maxWidth: Self.logoSize.width,
            maxHeight: Self.logoSize.height,
            trimsPadding: true
        ) {
            Text(model.meta?.name ?? model.fallbackTitle)
                .font(Theme.Hero.titleFallbackFont)
                .foregroundStyle(Theme.Color.primaryText)
                .lineLimit(2)
                // Capped so a long no-logo title wraps instead of running into the credits column.
                .frame(maxWidth: Theme.Hero.titleMaxWidth, alignment: .leading)
        }
        // type · genre · genre + content-rating box, led by the streaming-provider badge.
        MetaChipRow(
            parts: model.vm.typeAndGenreParts,
            trailingBadge: model.vm.displayCertification,
            leading: .provider(model.enrichment?.providerBadgeURL)
        )
        // A show under way describes its up-next episode, as Apple TV+ does; otherwise the logline.
        if let synopsis = model.heroEpisodeSynopsis(model.upNext()) {
            EpisodeHeroDescription(label: synopsis.label, overview: synopsis.overview)
        } else if let description = model.vm.displayDescription, !description.isEmpty {
            HeroDescription(text: description)
        }
        HeroFactsLine(text: model.vm.factsLine)
    }
}
