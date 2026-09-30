import SwiftUI

/// The title hero's text block: logo, type/genre chips with the certification box, synopsis, and the
/// facts line. Shared by the detail hero and the row preview so both read identically.
struct DetailHeroInfo: View {
    let model: MetaDetailModel

    var body: some View {
        // Per-title logo art, scaled to the reference (block ≈ 278 × 119, wordmark ≈ 14% of width).
        HeroTitleArt(
            logoURL: model.vm.displayLogoURL,
            accessibilityName: model.meta?.name ?? model.fallbackTitle,
            maxWidth: 280,
            maxHeight: 120
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
        if let description = model.vm.displayDescription, !description.isEmpty {
            HeroDescription(text: description)
        }
        HeroFactsLine(text: model.vm.factsLine)
    }
}
