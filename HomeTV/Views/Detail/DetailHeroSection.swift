import SwiftUI

/// State-A hero: the title/logo, chips, synopsis, facts, and action row bottom-anchored to the
/// lower-left, with the cast/credits floated in the upper-right. Fades and drifts up on the collapse
/// clock (`scroll.heroOpacity` / the parallax offset).
struct DetailHeroSection: View {
    let model: MetaDetailModel
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

    /// State-A column bottom-anchored to the lower-left, with the cast/credits floated in the upper-right
    /// region (vertically independent of the column). The column fills the hero frame so the action row
    /// settles near the bottom safe area.
    private var heroContent: some View {
        ZStack(alignment: .bottomLeading) {
            // Credits share the action row's bottom baseline (rule 4): bottom-trailing, right edge at the
            // right-margin token (≈ x 1760; leftInset 86 + 74 trailing = 160 from the right). Grows up.
            creditsColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 0)

            VStack(alignment: .leading, spacing: 16) {   // tighter rhythm pulls the upper stack down ~25 px
                titleView
                chipLine
                if let description = model.vm.displayDescription, !description.isEmpty {
                    HeroDescription(text: description)
                }
                metaLine
                actionButtons
            }
        }
        .padding(.horizontal, Theme.Detail.leftInset)
        .padding(.bottom, 40)   // sit the action row near the bottom safe area (≈ 88% down)
        .opacity(scroll.heroOpacity)   // Group A fades as it translates up (the scroll provides the translation)
        .focusSection()
    }

    // Per-title logo art, scaled to the reference (block ≈ 278 × 119, wordmark ≈ 14% of width). No
    // shadow here — the Detail hero doesn't lift the logo the way the Watch Now hero does.
    private var titleView: some View {
        HeroTitleArt(
            logoURL: model.vm.displayLogoURL,
            accessibilityName: model.meta?.name ?? model.fallbackTitle,
            maxWidth: 280,
            maxHeight: 120
        ) {
            titleTextFallback
        }
    }

    private var titleTextFallback: some View {
        Text(model.meta?.name ?? model.fallbackTitle)
            .font(Theme.Hero.titleFallbackFont)
            .foregroundStyle(Theme.Color.primaryText)
            .lineLimit(2)
            // Cap the width like the Watch Now fallback so a long no-logo title wraps instead of running
            // into the credits column on the right.
            .frame(maxWidth: Theme.Hero.titleMaxWidth, alignment: .leading)
    }

    // type · genre · genre  +  content-rating box (TMDB certification, with a placeholder fallback)
    // and a leading streaming-provider / network badge. Reuses the shared `MetaChipRow`.
    private var chipLine: some View {
        MetaChipRow(parts: model.vm.typeAndGenreParts, trailingBadge: model.vm.displayCertification,
                    leading: .provider(model.enrichment?.providerBadgeURL))
    }

    // year · runtime · ★ imdb  +  quality badges (PLACEHOLDER until addons provide them)
    private var metaLine: some View {
        HStack(spacing: 14) {
            Text(model.vm.factsLine)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Theme.Color.primaryText)
            QualityBadges()
        }
    }

    /// The show hero's up-next episode (resume / next-to-watch). Pure algorithm in the model over the
    /// cached episode list; the live Trakt watch state is injected here.
    private var seriesUpNext: MetaDetailViewModel.UpNext? {
        model.upNext(
            progress: { trakt.progress(forKey: model.vm.episodeKey($0)) },
            isWatched: { trakt.isWatched(type: model.typeID, imdb: model.metaID, season: $0.season, episode: $0.episode) }
        )
    }

    /// Play button label: episode-aware for series; Resume/Rewatch/Play for movies (Trakt state).
    private var playButtonTitle: String {
        if let upNext = seriesUpNext { return upNext.label }
        guard trakt.isSignedIn else { return "Play" }
        if trakt.progress(forKey: model.metaID) != nil { return "Resume" }
        if trakt.isWatched(type: model.typeID, imdb: model.metaID) { return "Rewatch" }
        return "Play"
    }

    /// Open the stream picker for what Play should play: a series' up-next episode (so stream addons,
    /// which key off the `tt…:S:E` episode id, return results), or the movie itself.
    private func startPlayback() {
        model.recordHistory()
        if let upNext = seriesUpNext {
            streamRequest = StreamRequest(
                type: model.typeID,
                contentID: upNext.video.id,
                title: model.meta.map { "\($0.name) — \(model.vm.episodeLabel(upNext.video))" } ?? model.vm.episodeLabel(upNext.video),
                backgroundURL: upNext.video.thumbnail ?? model.meta?.background,
                logoURL: model.meta?.logo
            )
        } else {
            streamRequest = StreamRequest(
                type: model.typeID,
                contentID: model.metaID,
                title: model.meta?.name ?? model.fallbackTitle,
                backgroundURL: model.meta?.background,
                logoURL: model.meta?.logo
            )
        }
    }

    // Reuses the shared hero buttons (HeroPlayButton / HeroCircleButton) from the home hero. Every button
    // reports `zone == .hero` while focused; moving focus down to the content flips the zone and drives
    // the full-viewport scroll. (Applying `.focused` externally works here as in HeroOverlay's HeroActionRow.)
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
                // Watched eye. For a show it marks the episode the Play pill resumes; for a movie it
                // marks the movie. No eye on a plain "Play" show (no specific episode to mark).
                if let upNext = seriesUpNext, upNext.marksEpisode {
                    let s = upNext.video.season ?? 0
                    let e = upNext.video.episode ?? 0
                    let watched = trakt.isWatched(type: model.typeID, imdb: model.metaID, season: s, episode: e)
                    HeroCircleButton(
                        icon: watched ? "eye.slash" : "eye",
                        accessibilityLabel: watched
                            ? "Mark \(model.vm.seasonEpisodeLabel(upNext.video)) Unwatched"
                            : "Mark \(model.vm.seasonEpisodeLabel(upNext.video)) Watched"
                    ) {
                        trakt.toggleEpisodeWatched(showIMDB: model.metaID, season: s, episode: e)
                    }
                    .focused(zone, equals: .hero)
                } else if model.typeID != "series" {
                    let watched = trakt.isWatched(type: model.typeID, imdb: model.metaID)
                    HeroCircleButton(
                        icon: watched ? "eye.slash" : "eye",
                        accessibilityLabel: watched ? "Mark as Unwatched" : "Mark as Watched"
                    ) {
                        trakt.toggleWatched(type: model.typeID, imdb: model.metaID)
                    }
                    .focused(zone, equals: .hero)
                }
            } else {
                HeroCircleButton(icon: "plus", accessibilityLabel: "Add to Up Next") { }
                    .focused(zone, equals: .hero)
            }
            HeroCircleButton(icon: "square.and.arrow.up", accessibilityLabel: "Share") { }
                .focused(zone, equals: .hero)
        }
        .padding(.top, 6)
    }

    @ViewBuilder
    private var creditsColumn: some View {
        let cast = model.vm.displayCastNames
        let directors = model.vm.displayDirectors
        if !cast.isEmpty || !directors.isEmpty {
            // Tight gap between credit lines so "Director" sits just under the cast block (the wrapped
            // cast names already span their own lines); a larger spacing reads as a gap above Director.
            VStack(alignment: .leading, spacing: 4) {
                if !cast.isEmpty {
                    creditLine(label: "Starring", names: Array(cast.prefix(3)))
                }
                if !directors.isEmpty {
                    creditLine(label: "Director", names: directors)
                }
            }
            .frame(maxWidth: 400, alignment: .leading)
        }
    }

    // Left-aligned, ragged-right: the dimmer label sits inline ahead of the brighter names, wrapping.
    private func creditLine(label: String, names: [String]) -> some View {
        (
            Text("\(label) ").foregroundStyle(Theme.Color.primaryText.opacity(0.5))
            + Text(names.joined(separator: ", ")).foregroundStyle(Theme.Color.primaryText)
        )
        .font(.system(size: 24))
        .multilineTextAlignment(.leading)
        .lineLimit(2)
    }
}
