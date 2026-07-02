import SwiftUI

/// State-A hero for a single episode: the show name, episode title, chips, `S·E`-prefixed synopsis,
/// facts, and action row bottom-anchored to the lower-left over the episode still. The episode analogue
/// of `DetailHeroSection` — reuses the same shared hero building blocks and the same collapse-clock
/// fade/parallax — but with a text title (episodes have no logo) and no credits column.
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
            titleView
            chipLine
            descriptionView
            metaLine
            actionButtons
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(.horizontal, Theme.Detail.leftInset)
        .padding(.bottom, 40)   // sit the action row near the bottom safe area (≈ 88% down)
        .opacity(scroll.heroOpacity)
        .focusSection()
    }

    // MARK: - Content

    /// Show name (muted, above) + episode title (large). No logo art — an episode has none.
    private var titleView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.meta?.name ?? model.fallbackTitle)
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

    // genre · genre + content-rating box, with a leading streaming-provider badge (Apple TV+ style — no
    // badge when the title isn't on a known provider). The episode chips drop the type label the show
    // hero carries, matching the reference.
    private var chipLine: some View {
        MetaChipRow(
            parts: Array(model.vm.displayGenres.splitGenres().prefix(2)),
            trailingBadge: model.vm.displayCertification,
            leading: .provider(model.enrichment?.providerBadgeURL)
        )
    }

    // "S1, E1:  <overview>" — the season/episode label bolded ahead of the synopsis, at the shared hero
    // description styling so it reads identically to the title detail's logline.
    @ViewBuilder
    private var descriptionView: some View {
        if let overview = episodeOverview, !overview.isEmpty {
            (
                Text("\(model.vm.seasonEpisodeLabel(episode)):  ")
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

    // air date · runtime + quality badges (PLACEHOLDER quality until addons provide them).
    private var metaLine: some View {
        HStack(spacing: 14) {
            Text(factsLine)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Theme.Color.primaryText)
            QualityBadges()
        }
    }

    // Reuses the shared hero buttons. Every button reports `zone == .hero` while focused; moving focus
    // down to the content flips the zone and drives the full-viewport collapse scroll.
    private var actionButtons: some View {
        HStack(spacing: 18) {
            HeroPlayButton(title: playButtonTitle, icon: "play.fill") { startPlayback() }
                .focused(zone, equals: .hero)
            if trakt.isSignedIn {
                let inWatchlist = trakt.isInWatchlist(imdb: model.metaID)
                HeroCircleButton(
                    icon: inWatchlist ? "checkmark" : "plus",
                    accessibilityLabel: inWatchlist ? "Remove from Watchlist" : "Add to Watchlist"
                ) {
                    trakt.toggleWatchlist(type: model.typeID, imdb: model.metaID)
                }
                .focused(zone, equals: .hero)
                HeroCircleButton(
                    icon: watched ? "eye.slash" : "eye",
                    accessibilityLabel: watched
                        ? "Mark \(model.vm.seasonEpisodeLabel(episode)) Unwatched"
                        : "Mark \(model.vm.seasonEpisodeLabel(episode)) Watched"
                ) {
                    trakt.toggleEpisodeWatched(
                        showIMDB: model.metaID,
                        season: episode.season ?? 0,
                        episode: episode.episode ?? 0
                    )
                }
                .focused(zone, equals: .hero)
            } else {
                HeroCircleButton(icon: "plus", accessibilityLabel: "Add to Up Next") { }
                    .focused(zone, equals: .hero)
            }
            HeroCircleButton(icon: "square.and.arrow.up", accessibilityLabel: "Share") { }
                .focused(zone, equals: .hero)
        }
        .padding(.top, 6)
    }

    // MARK: - Derived values

    private var episodeTitle: String {
        info?.title ?? episode.title ?? "Episode \(episode.episode ?? 0)"
    }

    private var episodeOverview: String? {
        info?.overview ?? episode.overview
    }

    private var factsLine: String {
        [model.vm.airDate(episode.released),
         model.vm.episodeDurationText(episode, info: info, width: .abbreviated)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var watched: Bool {
        trakt.isWatched(type: model.typeID, imdb: model.metaID, season: episode.season, episode: episode.episode)
    }

    /// Play / Resume / Rewatch for this specific episode, from Trakt state.
    private var playButtonTitle: String {
        guard trakt.isSignedIn else { return "Play" }
        if trakt.progress(forKey: model.vm.episodeKey(episode)) != nil { return "Resume" }
        if watched { return "Rewatch" }
        return "Play"
    }

    /// Open the stream picker for this episode (its `tt…:S:E` id is what stream addons key off).
    private func startPlayback() {
        model.recordHistory()
        streamRequest = StreamRequest(
            type: model.typeID,
            contentID: episode.id,
            title: model.meta.map { "\($0.name) — \(model.vm.episodeLabel(episode))" } ?? model.vm.episodeLabel(episode),
            backgroundURL: episode.thumbnail ?? model.meta?.background,
            logoURL: model.meta?.logo
        )
    }
}
