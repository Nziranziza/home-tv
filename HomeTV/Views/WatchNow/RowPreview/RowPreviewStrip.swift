import SwiftUI

/// The row preview's thumbnail strip: a series' episodes (from the up-next one), or a movie's related
/// titles. Reuses the detail screen's `EpisodeCard` and the row `ContentCard`.
struct RowPreviewStrip: View {
    let detail: MetaDetailModel
    var focus: FocusState<RowPreviewGallery.Control?>.Binding
    let onPlay: (StreamRequest) -> Void
    let onOpenEpisode: (Video) -> Void
    let onOpenRelated: (MetaPreview) -> Void

    @State private var position = ScrollPosition(idType: String.self)
    /// The last card with focus, for the leading barrier to hand focus back to.
    @State private var lastFocused = 0
    /// The season of the focused episode, so its TMDB data loads as you scroll into it.
    @State private var focusedSeason: Int?

    /// Episodes for a series; related titles only for a movie.
    static func hasContent(_ detail: MetaDetailModel) -> Bool {
        !detail.sortedEpisodes.isEmpty || (detail.typeID == "movie" && !detail.vm.relatedItems.isEmpty)
    }

    var body: some View {
        let vm = detail.vm
        let upNext = detail.upNext(
            progress: { UserLibrary.progress(forKey: vm.episodeKey($0)) },
            isWatched: { UserLibrary.isEpisodeWatched(type: detail.typeID, showID: detail.metaID, season: $0.season, episode: $0.episode) }
        )
        let upNextID = upNext.flatMap { $0.marksEpisode ? $0.video.id : nil }
        let season = focusedSeason ?? upNext?.video.season ?? detail.seasons.first
        let width = Theme.RowPreview.stripCardWidth
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: Theme.RowPreview.stripSpacing) {
                if detail.sortedEpisodes.isEmpty {
                    ForEach(vm.relatedItems.enumerated(), id: \.element.id) { i, item in
                        ContentCard(meta: item, shape: .landscape, sizeOverride: CGSize(width: width, height: width * 9 / 16)) {
                            onOpenRelated(item)
                        }
                        .focused(focus, equals: .strip(i))
                    }
                } else {
                    let ratingText = vm.displayCertification
                    ForEach(detail.sortedEpisodes.enumerated(), id: \.element.id) { i, episode in
                        let info = detail.episodeInfo[Enrichment.episodeKey(season: episode.season ?? 0, episode: episode.episode ?? 0)]
                        EpisodeCard(
                            thumbnailURL: info?.stillURL ?? episode.thumbnail.flatMap(URL.init(string:)),
                            episodeNumber: episode.episode ?? 0,
                            title: info?.title ?? episode.episodeTitle ?? "Episode \(episode.episode ?? 0)",
                            overview: info?.overview ?? episode.overview,
                            dateText: detail.episodeAirDateText[episode.id],
                            durationText: vm.episodeDurationText(episode, info: info),
                            ratingText: ratingText,
                            progress: UserLibrary.progress(forKey: vm.episodeKey(episode)),
                            watched: UserLibrary.isEpisodeWatched(type: detail.typeID, showID: detail.metaID, season: episode.season, episode: episode.episode),
                            isUpNext: episode.id == upNextID,
                            onFocusChange: { if $0 { focusedSeason = episode.season } },
                            onToggleWatched: episode.season != nil && episode.episode != nil ? {
                                UserLibrary.toggleEpisodeWatched(showID: detail.metaID, season: episode.season, episode: episode.episode)
                            } : nil,
                            onOpenDetail: { onOpenEpisode(episode) },
                            width: width
                        ) {
                            detail.recordHistory()
                            onPlay(StreamRequest(
                                type: detail.typeID,
                                contentID: episode.id,
                                title: detail.meta.map { "\($0.name) — \(vm.episodeLabel(episode))" } ?? vm.episodeLabel(episode),
                                backgroundURL: episode.thumbnail ?? detail.meta?.background,
                                logoURL: detail.meta?.logo
                            ))
                        }
                        .focused(focus, equals: .strip(i))
                    }
                }
            }
            .scrollTargetLayout()
            .detailRowContentPadding(0)
        }
        // Margins rather than padding, so scrolling to the up-next episode keeps it under Play.
        .contentMargins(.horizontal, Theme.RowPreview.infoLeading, for: .scrollContent)
        .scrollPosition($position, anchor: .leading)
        .detailRowScroll()
        // A horizontal scroll view is vertically flexible; keep it to the cards' height.
        .fixedSize(horizontal: false, vertical: true)
        .focusSection()
        // Left off the first card would otherwise open the sidebar.
        .focusBarrier(.leading, isActive: isFocused, gap: Theme.Hero.focusBarrierWidth) {
            Task { focus.wrappedValue = .strip(lastFocused) }
        }
        // The barrier widens the view on its leading side; shed that so the cards line up under Play.
        .padding(.leading, -Theme.Hero.focusBarrierWidth)
        .onChange(of: focus.wrappedValue) { _, new in
            if case .strip(let i) = new { lastFocused = i }
        }
        // Opens on the episode Play resumes, as the detail's episode row does.
        .onAppear {
            if let upNextID { position.scrollTo(id: upNextID, anchor: .leading) }
        }
        // TMDB stills and titles for the season in view, as the detail's episode row loads them.
        .task(id: "\(detail.metaID)|\(season ?? -1)") {
            await detail.loadSeasonEnrichment(season)
        }
    }

    private var isFocused: Bool {
        if case .strip = focus.wrappedValue { true } else { false }
    }
}
