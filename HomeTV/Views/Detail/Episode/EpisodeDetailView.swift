import SwiftUI

/// The single-episode detail screen — a lighter sibling of `MetaDetailView`: a near-full-height hero
/// (the episode still, title, synopsis, and actions) that collapses on scroll into a browse layout with
/// How to Watch and the Information / Languages / Accessibility footer.
///
/// It reuses the parent show's already-loaded `MetaDetailModel` rather than refetching: show-level data
/// (genres, certification, provider, how-to-watch, most of the info block) comes straight from the
/// model, and the episode-specific bits (still, synopsis, run time, air date) come from the passed
/// `Video` plus the model's per-episode TMDB `episodeInfo`. Both screens share `DetailScaffold`, so the
/// tuned collapse/scroll/zone machinery lives in one place.
struct EpisodeDetailView: View {
    /// The parent show model (reused — no refetch). Owned by the pushing `MetaDetailView`.
    let model: MetaDetailModel
    let episode: Video

    @State private var scroll = DetailScrollState()
    @State private var trakt = TraktService.shared
    @State private var streamRequest: StreamRequest?
    @FocusState private var zone: DetailZone?

    /// Per-episode TMDB info (still / synopsis / run time / title), if the show model has loaded this
    /// episode's season. Observing `model.episodeInfo` means the screen fills in once `loadSeasonEnrichment`
    /// completes below.
    private var info: EpisodeEnrichment? {
        model.episodeInfo[Enrichment.episodeKey(season: episode.season ?? 0, episode: episode.episode ?? 0)]
    }

    /// Backdrop = the episode still, falling back to the addon thumbnail and finally the show backdrop.
    private var backdropURL: URL? {
        info?.stillURL
            ?? episode.thumbnail.flatMap(URL.init(string:))
            ?? model.vm.backdropURL
    }

    private var episodeTitle: String {
        info?.title ?? episode.title ?? "Episode \(episode.episode ?? 0)"
    }

    var body: some View {
        DetailScaffold(scroll: scroll, zone: $zone) {
            EpisodeBackground(url: backdropURL, scroll: scroll)
        } content: { _ in
            EpisodeDetailContent(
                model: model, episode: episode, info: info, episodeTitle: episodeTitle,
                scroll: scroll, trakt: trakt, streamRequest: $streamRequest, zone: $zone
            )
        }
        // Ensure this episode's season enrichment is present even if it wasn't the season scrolled into
        // view when the episode was opened (the show model loads season info lazily). No-op if already loaded.
        .task(id: episode.season ?? -1) { await model.loadSeasonEnrichment(episode.season) }
        .streamPickerCover(request: $streamRequest)
    }
}

/// The scrolling content column for the episode screen: hero → centered title + How to Watch (the top
/// content row that peeks and drives the collapse) → the shared Information footer with the episode's own
/// release year and run time.
private struct EpisodeDetailContent: View {
    let model: MetaDetailModel
    let episode: Video
    let info: EpisodeEnrichment?
    let episodeTitle: String
    let scroll: DetailScrollState
    let trakt: TraktService
    @Binding var streamRequest: StreamRequest?
    var zone: FocusState<DetailZone?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: DetailLayout.interSectionSpacing) {
            EpisodeHeroSection(
                model: model, episode: episode, info: info,
                scroll: scroll, trakt: trakt, streamRequest: $streamRequest, zone: zone
            )
            // Cancel the browse-top-inset + hero-pull so the How to Watch row peeks below the hero at rest
            // (State A) and rests clear of the pinned title in browse (State B) — same contract as the
            // title detail's first content row.
            .padding(.bottom, -(DetailLayout.heroBottomPull + DetailLayout.browseTopInset))

            VStack(alignment: .leading, spacing: 0) {
                EpisodeCenteredTitle(title: episodeTitle, scroll: scroll)
                if !model.vm.watchOptions.isEmpty {
                    // Top content row: its cards carry the content zone so Down from the hero collapses.
                    DetailHowToWatchSection(model: model, scroll: scroll, zone: zone)
                }
            }
            .id("contentTop")

            DetailInformationSection(
                model: model,
                releasedOverride: episodeReleaseYear,
                runtimeOverride: model.vm.episodeDurationText(episode, info: info, width: .abbreviated)
            )
        }
    }

    /// The episode's air year (from its ISO release date), falling back to the show's release info.
    private var episodeReleaseYear: String? {
        if let released = episode.released, released.count >= 4 { return String(released.prefix(4)) }
        return model.meta?.releaseInfo
    }
}
