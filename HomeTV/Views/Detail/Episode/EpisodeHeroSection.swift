import SwiftUI

/// State-A hero for a single episode: the show name, episode title, chips, `S·E`-prefixed synopsis,
/// facts, and action row bottom-anchored to the lower-left over the episode still. The episode analogue
/// of `DetailHeroSection` — reuses the same shared hero building blocks and the same collapse-clock
/// fade/parallax — but with a text title (episodes have no logo) and no credits column. Its rows are
/// standalone `View` structs (`EpisodeHeroTitle`, `EpisodeHeroDescription`, `EpisodeHeroMetaLine`,
/// `EpisodeHeroActionButtons`) so SwiftUI can diff and re-render them independently.
struct EpisodeHeroSection: View {
    let model: MetaDetailModel
    let episode: Video
    let info: EpisodeEnrichment?
    let scroll: DetailScrollState
    let trakt: TraktService
    @Binding var streamRequest: StreamRequest?
    var zone: FocusState<DetailZone?>.Binding

    var body: some View {
        heroContent
            .containerRelativeFrame(.vertical) { length, _ in length * DetailLayout.heroHeightFraction }
            .ignoresSafeArea(edges: [.horizontal, .top])
            .id("heroTop")
            .offset(y: -max(scroll.offset, 0) * DetailLayout.heroParallax)   // render-only parallax drift
    }

    /// The State-A column, bottom-anchored to the lower-left and filling the hero frame so the action row
    /// settles near the bottom safe area. Fades as it translates up on the collapse clock.
    private var heroContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            EpisodeHeroTitle(showName: model.meta?.name ?? model.fallbackTitle, episodeTitle: episodeTitle)
            // genre · genre + content-rating box, with a leading streaming-provider badge (Apple TV+ style
            // — no badge when the title isn't on a known provider). The episode chips drop the type label
            // the show hero carries, matching the reference.
            MetaChipRow(
                parts: Array(model.vm.displayGenres.splitGenres().prefix(2)),
                trailingBadge: model.vm.displayCertification,
                leading: .provider(model.enrichment?.providerBadgeURL)
            )
            if let overview = episodeOverview, !overview.isEmpty {
                EpisodeHeroDescription(label: model.vm.seasonEpisodeLabel(episode), overview: overview)
            }
            EpisodeHeroMetaLine(factsLine: factsLine)
            EpisodeHeroActionButtons(
                model: model, episode: episode, trakt: trakt, streamRequest: $streamRequest, zone: zone
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(.horizontal, Theme.Detail.leftInset)
        .padding(.bottom, 40)   // sit the action row near the bottom safe area (≈ 88% down)
        .opacity(scroll.heroOpacity)
        .focusSection()
    }

    // MARK: - Derived values

    private var episodeTitle: String {
        info?.title ?? episode.title ?? "Episode \(episode.episode ?? 0)"
    }

    private var episodeOverview: String? {
        info?.overview ?? episode.overview
    }

    /// air date · runtime, joined for the meta line.
    private var factsLine: String {
        [model.vm.airDate(episode.released),
         model.vm.episodeDurationText(episode, info: info, width: .abbreviated)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
