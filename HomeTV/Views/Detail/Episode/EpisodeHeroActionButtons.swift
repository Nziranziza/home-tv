import SwiftUI

/// The episode hero's action row: Play/Resume/Rewatch for this specific episode, plus watchlist,
/// watched-eye, and share. Reuses the shared hero buttons. Every button reports `zone == .hero` while
/// focused; moving focus down to the content flips the zone and drives the full-viewport collapse scroll.
struct EpisodeHeroActionButtons: View {
    let model: MetaDetailModel
    let episode: Video
    let trakt: TraktService
    @Binding var streamRequest: StreamRequest?
    var zone: FocusState<DetailZone?>.Binding

    var body: some View {
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
                    // Only toggle when the episode is actually numbered — coercing nil to 0 would write a
                    // bogus 0:0 record that the `watched` check (which passes the optionals through) never sees.
                    guard let season = episode.season, let episodeNumber = episode.episode else { return }
                    trakt.toggleEpisodeWatched(showIMDB: model.metaID, season: season, episode: episodeNumber)
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
