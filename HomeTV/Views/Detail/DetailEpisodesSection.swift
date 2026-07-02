import SwiftUI

/// The episodes row: a single continuous horizontal strip spanning all seasons (Apple TV style), with
/// a season selector above that acts as a "jump to" control and stays in sync with whichever season is
/// scrolled into view.
///
/// Performance: this view does NOT read the scroll clock, so it isn't re-evaluated on every scroll
/// frame — only the leaf `SeasonSelectorBar` (its opacity fade) does. The episode list iterates the
/// model's cached `sortedEpisodes` (no per-frame sort) inside a `LazyHStack` (only ~6 cards realized),
/// and the hero up-next episode is computed once per render rather than per card.
struct DetailEpisodesSection: View {
    let model: MetaDetailModel
    let scroll: DetailScrollState
    let trakt: TraktService
    @Binding var streamRequest: StreamRequest?
    /// Set when an episode's description is selected → the parent pushes the episode detail screen.
    @Binding var episodeSelection: Video?
    var zone: FocusState<DetailZone?>.Binding

    @State private var selectedSeason: Int?
    @FocusState private var focusedSeason: Int?
    @State private var didRevealUpNext = false

    private var currentSeason: Int? { selectedSeason ?? model.seasons.first }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 18) {
                // The row header sits in a fixed-height slot (see `detailRowHeader`) so the episode peek
                // below is identical whether this is a one-line label or the taller season selector.
                header(proxy: proxy)
                episodeStrip(proxy: proxy)
            }
            // Focusing a season tab (not clicking) jumps the episode strip to that season.
            // A tab gained focus: either via the focus guide redirecting re-entry to the selected season
            // (a no-op scroll), or deliberate tab-to-tab navigation. Either way, jump the strip to it —
            // `selectSeason` only scrolls when the season actually changed.
            .onChange(of: focusedSeason) { _, newValue in
                guard let newValue else { return }
                selectSeason(newValue, proxy: proxy)
            }
            // On load, reveal the up-next episode: select its season and scroll the strip to it, so the
            // episode the hero Play targets is what you see first (instead of always S1, E1).
            .onChange(of: model.sortedEpisodes.count) { _, count in
                guard count > 0, !didRevealUpNext,
                      let upNext = seriesUpNext, upNext.marksEpisode else { return }
                didRevealUpNext = true
                selectedSeason = upNext.video.season
                withAnimation(.easeOut(duration: 0.35)) {
                    proxy.scrollTo(upNext.video.id, anchor: .leading)
                }
            }
            // Fetch TMDB episode info for the season in view, lazily — re-runs when the selected season
            // (or the title) changes. Scoped by metaID so a new title always refetches. Bounds requests
            // for long-running shows.
            .task(id: "\(model.metaID)|\(currentSeason ?? -1)") {
                await model.loadSeasonEnrichment(currentSeason)
            }
        }
    }

    @ViewBuilder
    private func header(proxy: ScrollViewProxy) -> some View {
        // The selector fades out in the hero state — like every section label — leaving only the peeking
        // episodes, and fades back in as the season-jump control in browse.
        if model.seasons.count > 1 {
            SeasonSelectorBar(
                seasons: model.seasons,
                currentSeason: currentSeason,
                scroll: scroll,
                focusedSeason: $focusedSeason
            ) { season in
                selectSeason(season, proxy: proxy)
            }
            .detailRowHeader()
        } else {
            DetailSectionHeader(title: "Episodes", scroll: scroll)
                .detailRowHeader()
        }
    }

    private func episodeStrip(proxy: ScrollViewProxy) -> some View {
        let vm = model.vm
        // Computed once per render (over the cached, already-sorted episode list) — not per card.
        let upNext = seriesUpNext
        let upNextID = upNext?.marksEpisode == true ? upNext?.video.id : nil
        return ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 28) {
                ForEach(model.sortedEpisodes) { episode in
                    let info = model.episodeInfo[Enrichment.episodeKey(season: episode.season ?? 0, episode: episode.episode ?? 0)]
                    EpisodeCard(
                        thumbnailURL: info?.stillURL ?? episode.thumbnail.flatMap(URL.init(string:)),
                        episodeNumber: episode.episode ?? 0,
                        title: info?.title ?? episode.title ?? "Episode \(episode.episode ?? 0)",
                        overview: info?.overview ?? episode.overview,
                        dateText: vm.airDate(episode.released),
                        durationText: vm.episodeDurationText(episode, info: info),
                        ratingText: vm.displayCertification,
                        progress: trakt.progress(forKey: vm.episodeKey(episode)),
                        watched: trakt.isWatched(type: model.typeID, imdb: model.metaID, season: episode.season, episode: episode.episode),
                        isUpNext: episode.id == upNextID,
                        onFocusChange: { isFocused in
                            if isFocused { episodeFocused(episode, proxy: proxy) }
                        },
                        onToggleWatched: trakt.isSignedIn ? {
                            trakt.toggleEpisodeWatched(
                                showIMDB: model.metaID,
                                season: episode.season ?? 0,
                                episode: episode.episode ?? 0
                            )
                        } : nil,
                        // Description → open the episode detail screen (reuses the loaded show model).
                        onOpenDetail: { episodeSelection = episode }
                    ) {
                        // Thumbnail → play the episode.
                        streamRequest = StreamRequest(
                            type: model.typeID,
                            contentID: episode.id,
                            title: model.meta.map { "\($0.name) — \(vm.episodeLabel(episode))" } ?? vm.episodeLabel(episode),
                            backgroundURL: episode.thumbnail ?? model.meta?.background,
                            logoURL: model.meta?.logo
                        )
                    }
                    .id(episode.id)
                    // The episode strip is the focus entry from the hero: the season selector is hidden
                    // (faded) in the hero state, so Down lands here and drives the scroll.
                    .contentZone(true, zone)
                }
            }
            .padding(.horizontal, Theme.Detail.leftInset)
            .padding(.vertical, 24)
        }
        .detailRowScroll()
        .focusSection()
    }

    /// The hero's up-next episode (resume / next-to-watch), over the cached episode list with live Trakt
    /// state injected. Used to mark the matching card with the "Up Next" badge.
    private var seriesUpNext: MetaDetailViewModel.UpNext? {
        model.upNext(
            progress: { trakt.progress(forKey: model.vm.episodeKey($0)) },
            isWatched: { trakt.isWatched(type: model.typeID, imdb: model.metaID, season: $0.season, episode: $0.episode) }
        )
    }

    /// Triggered when a season tab gains focus (or is clicked): highlight it and scroll the continuous
    /// episode strip to that season's first episode. No click required — focus alone drives it. Only
    /// jumps the strip when the season actually changes, so returning focus to the *already selected*
    /// season (Up from its episodes) keeps your place in the strip instead of resetting to its first
    /// episode.
    private func selectSeason(_ season: Int, proxy: ScrollViewProxy) {
        let changed = selectedSeason != season
        selectedSeason = season
        guard changed, let target = model.firstEpisodeID(of: season) else { return }
        withAnimation(.easeOut(duration: 0.35)) {
            proxy.scrollTo(target, anchor: .leading)
        }
    }

    /// Triggered when an episode card gains focus: keep the season selector's highlight in sync with
    /// whichever season the focused episode belongs to (and scroll the selector to reveal that tab),
    /// so the header always reflects what you're looking at as you scroll across season boundaries.
    private func episodeFocused(_ episode: Video, proxy: ScrollViewProxy) {
        let season = episode.season
        guard selectedSeason != season else { return }
        selectedSeason = season
        if let season {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo("season-\(season)", anchor: .center)
            }
        }
    }
}

/// The horizontally scrollable season tabs. Fades on the collapse clock (a leaf that reads `scroll`)
/// so the episode strip beside it stays off the scroll-render path.
private struct SeasonSelectorBar: View {
    let seasons: [Int]
    let currentSeason: Int?
    let scroll: DetailScrollState
    var focusedSeason: FocusState<Int?>.Binding
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(seasons, id: \.self) { season in
                    Button { onSelect(season) } label: {
                        Text("Season \(season)")
                            .font(.system(size: 26, weight: .semibold))
                            .padding(.horizontal, 22)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(SeasonTabStyle(isSelected: currentSeason == season))
                    .focused(focusedSeason, equals: season)
                    .id("season-\(season)")
                }
            }
            .padding(.horizontal, Theme.Detail.leftInset)
            .padding(.vertical, 8)
        }
        .detailRowScroll()
        .focusSection()
        // Up from the episode strip would otherwise pick a tab by geometry (the one above the focused
        // episode), not the selected season. The focus guide redirects entry to the selected season's
        // tab. Above `.opacity` so the guide fades with the selector and is inert in the hero state.
        .focusGuide(focusedSeason, to: currentSeason)
        .opacity(scroll.logoReveal)
    }
}
