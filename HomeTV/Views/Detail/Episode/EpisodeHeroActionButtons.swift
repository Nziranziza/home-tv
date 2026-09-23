import SwiftUI

/// The episode hero's action row: Play/Resume/Rewatch for this specific episode, plus watchlist,
/// watched-eye, and share. Reuses the shared hero buttons, including the watchlist and share controls
/// it shares with the title detail hero. Every button reports `zone == .hero` while
/// focused; moving focus down to the content flips the zone and drives the full-viewport collapse scroll.
struct EpisodeHeroActionButtons: View {
    let model: MetaDetailModel
    let episode: Video
    @Binding var streamRequest: StreamRequest?
    var zone: FocusState<DetailZone?>.Binding

    var body: some View {
        HStack(spacing: Theme.Detail.heroActionRowSpacing) {
            HeroPlayButton(title: playButtonTitle, icon: "play.fill") { startPlayback() }
                .focused(zone, equals: .hero)
            HeroWatchlistButton(preview: model.preview)
                .focused(zone, equals: .hero)
            // Only for a numbered episode: an unnumbered video has no identity to record, and a
            // control that silently does nothing is worse than no control.
            if let season = episode.season, let episodeNumber = episode.episode {
                HeroCircleButton(
                    icon: watched ? "eye.slash" : "eye",
                    accessibilityLabel: watched
                        ? "Mark \(model.vm.seasonEpisodeLabel(episode)) Unwatched"
                        : "Mark \(model.vm.seasonEpisodeLabel(episode)) Watched"
                ) {
                    UserLibrary.toggleEpisodeWatched(
                        showID: model.metaID,
                        season: season,
                        episode: episodeNumber
                    )
                }
                .focused(zone, equals: .hero)
            }
            HeroShareButton()
                .focused(zone, equals: .hero)
        }
        .padding(.top, Theme.Detail.heroActionRowTopPadding)
    }

    private var watched: Bool {
        UserLibrary.isEpisodeWatched(type: model.typeID, showID: model.metaID, season: episode.season, episode: episode.episode)
    }

    /// Play / Resume / Rewatch for this specific episode.
    private var playButtonTitle: String {
        if UserLibrary.progress(forKey: model.vm.episodeKey(episode)) != nil { return "Resume" }
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
