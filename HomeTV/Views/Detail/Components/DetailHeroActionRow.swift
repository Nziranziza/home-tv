import SwiftUI

/// A button in the title hero's action row, so a host can give each its own focus value.
enum DetailHeroAction: Hashable { case play, watchlist, watched, share }

/// The title hero's action row: episode-aware Play, Watchlist, Watched and Share. Shared by the detail
/// hero and the row preview; `trailing` appends host-specific buttons.
struct DetailHeroActionRow<Focus: Hashable, Trailing: View>: View {
    let model: MetaDetailModel
    var focus: FocusState<Focus?>.Binding
    let focusValue: (DetailHeroAction) -> Focus
    let onPlay: (StreamRequest) -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        let upNext = seriesUpNext
        HStack(spacing: Theme.Detail.heroActionRowSpacing) {
            HeroPlayButton(title: playButtonTitle(upNext), icon: "play.fill") {
                onPlay(playbackRequest(upNext))
            }
            .focused(focus, equals: focusValue(.play))
            HeroWatchlistButton(preview: model.preview)
                .focused(focus, equals: focusValue(.watchlist))
            // Watched eye. For a show it marks the episode the Play pill resumes — recorded locally
            // when Trakt is not connected — and for a movie it marks the movie, which only Trakt can
            // hold. No eye on a plain "Play" show (no specific episode to mark).
            if let upNext, upNext.marksEpisode {
                let s = upNext.video.season ?? 0
                let e = upNext.video.episode ?? 0
                let watched = UserLibrary.isEpisodeWatched(type: model.typeID, showID: model.metaID, season: s, episode: e)
                HeroCircleButton(
                    icon: watched ? "eye.slash" : "eye",
                    accessibilityLabel: watched
                        ? "Mark \(model.vm.seasonEpisodeLabel(upNext.video)) Unwatched"
                        : "Mark \(model.vm.seasonEpisodeLabel(upNext.video)) Watched"
                ) {
                    UserLibrary.toggleEpisodeWatched(showID: model.metaID, season: s, episode: e)
                }
                .focused(focus, equals: focusValue(.watched))
            } else if model.typeID != "series" {
                let watched = UserLibrary.isWatched(type: model.typeID, id: model.metaID)
                HeroCircleButton(
                    icon: watched ? "eye.slash" : "eye",
                    accessibilityLabel: watched ? "Mark as Unwatched" : "Mark as Watched"
                ) {
                    UserLibrary.toggleWatched(type: model.typeID, id: model.metaID)
                }
                .focused(focus, equals: focusValue(.watched))
            }
            HeroShareButton()
                .focused(focus, equals: focusValue(.share))
            trailing()
        }
        .padding(.top, Theme.Detail.heroActionRowTopPadding)
    }

    /// The show hero's up-next episode (resume / next-to-watch), with the live watch state injected.
    private var seriesUpNext: MetaDetailViewModel.UpNext? {
        model.upNext(
            progress: { UserLibrary.progress(forKey: model.vm.episodeKey($0)) },
            isWatched: { UserLibrary.isEpisodeWatched(type: model.typeID, showID: model.metaID, season: $0.season, episode: $0.episode) }
        )
    }

    /// Episode-aware for series; Resume/Rewatch/Play for movies.
    private func playButtonTitle(_ upNext: MetaDetailViewModel.UpNext?) -> String {
        if let upNext { return upNext.label }
        if UserLibrary.progress(forKey: model.metaID) != nil { return "Resume" }
        if UserLibrary.isWatched(type: model.typeID, id: model.metaID) { return "Rewatch" }
        return "Play"
    }

    /// What Play opens the stream picker for: a series' up-next episode (stream addons key off the
    /// `tt…:S:E` episode id), or the movie itself. Records the title in history.
    private func playbackRequest(_ upNext: MetaDetailViewModel.UpNext?) -> StreamRequest {
        model.recordHistory()
        if let upNext {
            return StreamRequest(
                type: model.typeID,
                contentID: upNext.video.id,
                title: model.meta.map { "\($0.name) — \(model.vm.episodeLabel(upNext.video))" } ?? model.vm.episodeLabel(upNext.video),
                backgroundURL: upNext.video.thumbnail ?? model.meta?.background,
                logoURL: model.meta?.logo
            )
        }
        return StreamRequest(
            type: model.typeID,
            contentID: model.metaID,
            title: model.meta?.name ?? model.fallbackTitle,
            backgroundURL: model.meta?.background,
            logoURL: model.meta?.logo
        )
    }
}

extension DetailHeroActionRow where Trailing == EmptyView {
    init(
        model: MetaDetailModel,
        focus: FocusState<Focus?>.Binding,
        focusValue: @escaping (DetailHeroAction) -> Focus,
        onPlay: @escaping (StreamRequest) -> Void
    ) {
        self.init(model: model, focus: focus, focusValue: focusValue, onPlay: onPlay, trailing: { EmptyView() })
    }
}
