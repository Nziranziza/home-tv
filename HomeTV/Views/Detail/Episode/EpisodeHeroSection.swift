import SwiftUI

/// State-A hero for a single episode: the show name, episode title, chips, `S·E`-prefixed synopsis,
/// facts, and action row bottom-anchored to the lower-left over the episode still. The episode analogue
/// of `DetailHeroSection` — it stages (`DetailHeroStage`) and lays out (`DetailHeroColumn`) through the
/// same shared containers, so the two heroes share one rhythm, gutter, and collapse clock — but with a
/// text title (episodes have no logo) and no credits column. Its rows are standalone `View` structs
/// (`EpisodeHeroTitle`, `EpisodeHeroDescription`, `HeroFactsLine`, `EpisodeHeroActionButtons`) so SwiftUI
/// can diff and re-render them independently.
struct EpisodeHeroSection: View {
    let model: MetaDetailModel
    let episode: Video
    let info: EpisodeEnrichment?
    let scroll: DetailScrollState
    let trakt: TraktService
    @Binding var streamRequest: StreamRequest?
    var zone: FocusState<DetailZone?>.Binding

    var body: some View {
        // Like the title hero, the collapse clock is read inside `DetailHeroStage` / `DetailHeroColumn`,
        // not here — so a scroll tick re-applies an offset and an opacity instead of rebuilding this column.
        DetailHeroStage(scroll: scroll) {
            heroContent
        }
    }

    private var heroContent: some View {
        DetailHeroColumn(scroll: scroll) {
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
            HeroFactsLine(text: factsLine)
            EpisodeHeroActionButtons(
                model: model, episode: episode, trakt: trakt, streamRequest: $streamRequest, zone: zone
            )
        }
    }

    // MARK: - Derived values

    private var episodeTitle: String {
        info?.title ?? episode.title ?? "Episode \(episode.episode ?? 0)"
    }

    private var episodeOverview: String? {
        info?.overview ?? episode.overview
    }

    /// air date · runtime, joined for the facts line.
    private var factsLine: String {
        [model.vm.airDate(episode.released),
         model.vm.episodeDurationText(episode, info: info, width: .abbreviated)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
