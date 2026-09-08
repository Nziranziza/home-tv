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
        // The hero is framed and parallaxed by `DetailHeroStage`, which reads the scroll clock in a child
        // view rather than here — so this body doesn't depend on `scroll.offset` and is not re-evaluated on
        // every scroll tick. That keeps the per-tick rebuild (and the up-next episode scan it triggers,
        // see `seriesUpNext`) off the collapse animation.
        DetailHeroStage(scroll: scroll) {
            heroContent
        }
    }

    /// State-A column bottom-anchored to the lower-left, with the cast/credits floated in the
    /// bottom-trailing region. Container (rhythm, gutter, bottom inset, collapse fade, focus section) is
    /// the shared `DetailHeroColumn`, so this hero and the episode hero stay in step.
    private var heroContent: some View {
        DetailHeroColumn(scroll: scroll) {
            titleView
            chipLine
            if let description = model.vm.displayDescription, !description.isEmpty {
                HeroDescription(text: description)
            }
            HeroFactsLine(text: model.vm.factsLine)
            actionButtons
        } trailing: {
            creditsColumn
        }
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

    // Reuses the shared hero buttons (HeroPlayButton / HeroCircleButton) from the home hero, and the
    // watchlist/share controls it shares with the episode hero. Every button reports `zone == .hero` while
    // focused; moving focus down to the content flips the zone and drives the full-viewport scroll.
    // (Applying `.focused` externally works here as in HeroOverlay's HeroActionRow.)
    private var actionButtons: some View {
        HStack(spacing: Theme.Detail.heroActionRowSpacing) {
            HeroPlayButton(title: playButtonTitle, icon: "play.fill") { startPlayback() }
                .focused(zone, equals: .hero)
            HeroWatchlistButton(trakt: trakt, type: model.typeID, imdb: model.metaID)
                .focused(zone, equals: .hero)
            // Watched eye, signed in only. For a show it marks the episode the Play pill resumes; for a
            // movie it marks the movie. No eye on a plain "Play" show (no specific episode to mark).
            if trakt.isSignedIn {
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
            }
            HeroShareButton()
                .focused(zone, equals: .hero)
        }
        .padding(.top, Theme.Detail.heroActionRowTopPadding)
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
