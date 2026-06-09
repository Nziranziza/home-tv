import SwiftUI
import CoreText

struct MetaDetailView: View {
    let typeID: String
    let metaID: String
    let fallbackTitle: String

    /// Preview/sample injection only. When set, the screen renders this title instead of loading from
    /// addons — used by `#Preview` so the demo can match the reference clip offline. nil in the app.
    var previewMeta: Meta? = nil

    @State private var registry = AddonRegistry.shared
    @State private var trakt = TraktService.shared
    @State private var meta: Meta?
    /// TMDB enrichment sidecar, populated after the base meta loads. nil until then (or when TMDB
    /// isn't configured / the id isn't an IMDB id) — every consumer falls back to addon `meta`.
    @State private var enrichment: Enrichment?
    /// Per-episode TMDB info (runtime/still/overview/title), keyed by "season:episode". Filled lazily
    /// for the season currently in view (see `loadSeasonEnrichment`), merged over addon `Video` data.
    @State private var episodeInfo: [String: EpisodeEnrichment] = [:]
    @State private var seasonPosters: [Int: URL] = [:]
    @State private var status: LoadStatus = .loading
    @Environment(\.openURL) private var openURL
    @State private var related: [MetaPreview] = []
    @State private var selectedSeason: Int?
    @FocusState private var focusedSeason: Int?
    @State private var relatedSelection: MetaPreview?
    @State private var streamRequest: StreamRequest? = MetaDetailView.initialStreamRequest()
    @State private var didRevealUpNext = false
    @State private var scrollOffset: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    /// Which region currently holds focus. Crossing the hero↔content boundary drives the full-viewport scroll.
    @FocusState private var zone: Zone?

    enum Zone: Hashable { case hero, content }

    /// Scroll offset + viewport height, read on each scroll tick; drives the background blur ramp.
    private struct ScrollMetrics: Equatable {
        var offset: CGFloat
        var viewport: CGFloat
    }

    private static func initialStreamRequest() -> StreamRequest? {
        guard let raw = ProcessInfo.processInfo.environment["INITIAL_STREAM_PICKER"] else { return nil }
        let parts = raw.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return nil }
        return StreamRequest(
            type: parts[0],
            contentID: parts[1],
            title: parts.count >= 3 ? parts[2] : "Stream Picker"
        )
    }

    enum LoadStatus { case loading, loaded, failed }

    /// Pure presentation logic, built from the current data on each access. The view keeps owning all
    /// of its `@State`; this holds no state of its own (see `MetaDetailViewModel`).
    private var model: MetaDetailViewModel {
        MetaDetailViewModel(
            meta: meta, enrichment: enrichment, related: related,
            typeID: typeID, metaID: metaID, fallbackTitle: fallbackTitle
        )
    }

    var body: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()

            // Fixed background image; everything scrolls above it. A real Gaussian blur ramps with the
            // scroll (sharp behind the hero, blurred behind the content).
            pageBackground
                .ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: interSectionSpacing) {
                        // The first content row carries `browseTopInset` of top padding so that, when the
                        // collapse scrolls it to the top, it rests at ≈ y224 — clear of the pinned logo
                        // above it (State B). The hero's negative bottom inset cancels that padding (and
                        // more) at rest so the bare card still peeks below the hero in State A.
                        heroSection
                            .padding(.bottom, -(heroBottomPull + browseTopInset))
                        // The first content row is the scroll/collapse target ("contentTop") and the row
                        // that peeks: Episodes for a series, otherwise Trailers. The centered title logo
                        // occupies the `browseTopInset` band above it (replacing the old top padding), so
                        // it scrolls with the content and rests at the top in the browse state.
                        if !seasons.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                centeredLogo
                                episodesSection
                            }
                            .id("contentTop")
                            trailersSection
                        } else {
                            VStack(alignment: .leading, spacing: 0) {
                                centeredLogo
                                trailersSection
                            }
                            .id("contentTop")
                        }
                        if !relatedItems.isEmpty {
                            relatedSection.id("related")
                        }
                        if !watchOptions.isEmpty {
                            howToWatchSection
                        }
                        if !creditEntries.isEmpty {
                            castSection
                        }
                        aboutSection.id("about")
                        informationSection.id("information")
                    }
                    .environment(\.detailChromeOpacity, Double(logoReveal))
                }
                .scrollIndicators(.hidden)
                // Lay content out to the physical screen edges so the single `leftInset` guide is measured
                // from the same edge as the hero (which also ignores the horizontal safe area). Otherwise
                // the rows would inset by an extra safe-area margin and sit pushed-in relative to the hero.
                .ignoresSafeArea(edges: [.top, .horizontal])
                .contentMargins(.top, 0, for: .scrollContent)
                .onScrollGeometryChange(for: ScrollMetrics.self) {
                    ScrollMetrics(offset: $0.contentOffset.y, viewport: $0.containerSize.height)
                } action: { _, newValue in
                    scrollOffset = newValue.offset
                    viewportHeight = newValue.viewport
                }
                // Crossing the hero↔content boundary scrolls the full viewport (hero off / back).
                .onChange(of: zone) { _, newZone in
                    switch newZone {
                    case .content:
                        withAnimation(heroScroll) { proxy.scrollTo("contentTop", anchor: .top) }
                    case .hero:
                        withAnimation(heroScroll) { proxy.scrollTo("heroTop", anchor: .top) }
                    case .none:
                        break
                    }
                }
                .onChange(of: related.count) { _, newCount in
                    if newCount > 0,
                       let target = ProcessInfo.processInfo.environment["SCROLL_TO"] {
                        withAnimation { proxy.scrollTo(target, anchor: .top) }
                    }
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)   // full-screen detail (no tab bar over the content)
        .task(id: "\(typeID):\(metaID)") { await load() }
        .navigationDestination(item: $relatedSelection) { item in
            MetaDetailView(typeID: item.type, metaID: item.id, fallbackTitle: item.name)
        }
        .streamPickerCover(request: $streamRequest)
    }

    /// The single clock for the whole hero↔browse interaction. Translation, opacity, blur, brightness,
    /// saturation, the logo fade, and the trailer-card focus-lift are ALL functions of `p` and animate
    /// on this one spring — decelerating, no bounce, no overshoot. (Matches the reference exactly; the
    /// usual reason a copy looks "off" is desynced / differently-eased sub-animations.)
    private var heroScroll: Animation { .spring(response: 0.55, dampingFraction: 0.9) }

    /// Normalized collapse progress, the single source of truth: 0 = State A (hero), 1 = State B
    /// (browse). The animated scrollTo moves `scrollOffset` on the spring above, so every property
    /// expressed as a function of `p` shares that one clock.
    private var p: CGFloat {
        let denom = stateBScrollOffset
        guard denom > 0 else { return 0 }
        return min(max(scrollOffset / denom, 0), 1)
    }

    /// The scroll offset at the State-B rest position (contentTop pinned to the top). `p` normalizes to
    /// THIS, not the hero height — the hero/content paddings shrink the scroll distance, so normalizing
    /// by the hero height alone leaves p < 1 at rest and the sharp background layer bleeds through the
    /// blur. Mirrors the layout: hero region, minus its negative bottom inset, plus the section gap.
    private var stateBScrollOffset: CGFloat {
        viewportHeight * heroHeightFraction - (heroBottomPull + browseTopInset) + interSectionSpacing
    }

    /// Group A (the State-A content column) fades as it translates up — effectively transparent slightly
    /// before it clears the top (p ≈ 0.77). The floor stays just above 0 so the focus engine can still
    /// land on the hero buttons (tvOS won't focus an opacity-0 view); since the group is scrolled fully
    /// off-screen at State B, the floor is never visible — it only keeps Up (browse → hero) reachable.
    private var heroOpacity: CGFloat { max(0.02, 1 - min(1, p * 1.3)) }

    // MARK: - Background

    private var backdropURL: URL? { model.backdropURL }

    /// Two stacked layers crossfading on the `p` clock:
    ///  • Layer 2 (beneath, always present): the same still, Gaussian-blurred (radius 50), dimmed to
    ///    ~62% brightness and desaturated to 0.85, with a soft dark vignette — the State-B background.
    ///  • Layer 1 (sharp hero) fades out as `p → 1` (`opacity = 1 - p`), carrying the State-A scrims:
    ///    a left→right dark gradient (dark at x 0, clear by x ≈ 700) and a subtle bottom-up gradient.
    private var pageBackground: some View {
        ZStack {
            backgroundImage
                .blur(radius: 175)                                // very heavy wash — figures fully indistinct
                .saturation(1.05)                                 // keep/boost the warm tint (don't go neutral grey)
                .overlay(Color.black.opacity(0.16))               // ~lum 125 warm (reference target)
                .overlay(
                    RadialGradient(
                        colors: [.clear, .black.opacity(0.45)],
                        center: .center, startRadius: 220, endRadius: 1180
                    )
                    .allowsHitTesting(false)
                )

            backgroundImage
                .overlay(
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.78), location: 0.0),
                            .init(color: .clear, location: 0.40)   // transparent by x ≈ 700/1920
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .allowsHitTesting(false)
                )
                .overlay(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.5)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                )
                .opacity(1 - p)
        }
        .ignoresSafeArea()
    }

    /// Full-bleed backdrop image (GeometryReader gives a definite full-screen frame so it covers behind
    /// the hero and the content below it).
    private var backgroundImage: some View {
        GeometryReader { geo in
            RemoteImage(
                url: backdropURL,
                targetSize: Theme.Hero.backdropTargetSize,
                contentMode: .fill
            ) {
                Color(white: 0.05)
            }
            .scaledToFill()
            .frame(width: geo.size.width, height: geo.size.height)
            .scaleEffect(1.05) // small over-scale so the blur never softens a visible edge
            .clipped()
        }
        .ignoresSafeArea()
    }

    // MARK: - Hero

    /// Hero region height as a fraction of the (top-safe-area-ignored) viewport. Near-full so the State-A
    /// column bottom-anchors with the action row at ≈ 88% down (bottom edge y ≈ 957 / 1080), matching the
    /// reference, and so the collapse scrolls almost a full screen into the browse state.
    private let heroHeightFraction: CGFloat = 0.978

    /// Element B — the small centered title logo. Fades in around the midpoint of the collapse at its
    /// fixed top-center position (no large translation): `opacity = max(0, (p - 0.4) / 0.6)`.
    private var logoReveal: CGFloat { max(0, (p - 0.4) / 0.6) }

    /// Extra upward drift on the hero so it exits a bit faster than the content rises (× scroll speed).
    private let heroParallax: CGFloat = 0.3

    /// Top inset on the first content row so it rests at ≈ y224 (clear below the pinned logo) in State B.
    private let browseTopInset: CGFloat = 217

    /// Base upward pull on the content so the bare card peeks below the hero in State A (added to
    /// `browseTopInset` as the hero's negative bottom inset). Vertical gap between stacked sections.
    private let heroBottomPull: CGFloat = 110
    private let interSectionSpacing: CGFloat = 56

    private var heroSection: some View {
        heroContent
            .containerRelativeFrame(.vertical) { length, _ in length * heroHeightFraction }
            .ignoresSafeArea(edges: [.horizontal, .top])
            .id("heroTop")
            .offset(y: -max(scrollOffset, 0) * heroParallax)   // render-only parallax drift
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
                if let description = displayDescription, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 27))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineSpacing(6)               // ≈ line-height 1.25 at 27 pt
                        .lineLimit(4)
                        .frame(maxWidth: 780, alignment: .leading)   // wraps at ≈ x 746 from the x 86 guide
                }
                metaLine
                actionButtons
                resumeBar
            }
        }
        .padding(.horizontal, Theme.Detail.leftInset)
        .padding(.bottom, 40)   // sit the action row near the bottom safe area (≈ 88% down)
        .opacity(heroOpacity)   // Group A fades as it translates up (the scroll provides the translation)
        .focusSection()
    }

    @ViewBuilder
    private var titleView: some View {
        if let url = displayLogoURL {
            RemoteImage(url: url, targetSize: CGSize(width: 800, height: 220), contentMode: .fit) {
                titleTextFallback
            }
            // Per-title logo art, scaled to the reference (block ≈ 278 × 119, wordmark ≈ 14% of width).
            .frame(maxWidth: 280, maxHeight: 120, alignment: .bottomLeading)
            .accessibilityLabel(meta?.name ?? fallbackTitle)
        } else {
            titleTextFallback
        }
    }

    private var titleTextFallback: some View {
        Text(meta?.name ?? fallbackTitle)
            .font(.system(size: 52, weight: .heavy))
            .foregroundStyle(Theme.Color.primaryText)
            .lineLimit(2)
    }

    // MARK: - Centered content logo

    /// The title logo, centered at the top of the scrolling content (above Trailers). It's an in-flow
    /// item — it scrolls with the page, not pinned. It fills the `browseTopInset` band that rests at the
    /// top in the browse state, and fades on the collapse clock (`logoReveal`) so it never paints over
    /// the hero in State A (where this band is pulled up behind the hero).
    private var centeredLogo: some View {
        centeredLogoArt
            .frame(width: 228, height: 99)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 45)
            .frame(height: browseTopInset, alignment: .top)
            .opacity(logoReveal)
    }

    @ViewBuilder
    private var centeredLogoArt: some View {
        if let url = displayLogoURL {
            RemoteImage(url: url, targetSize: CGSize(width: 800, height: 220), contentMode: .fit) {
                centeredLogoFallback
            }
            .accessibilityLabel(meta?.name ?? fallbackTitle)
        } else {
            centeredLogoFallback
        }
    }

    private var centeredLogoFallback: some View {
        Text(meta?.name ?? fallbackTitle)
            .font(.system(size: 34, weight: .heavy))
            .foregroundStyle(Theme.Color.primaryText)
            .multilineTextAlignment(.center)
            .lineLimit(2)
    }

    // type · genre · genre  +  content-rating box (TMDB certification, with a placeholder fallback)
    // and a leading streaming-provider / network badge. Reuses the shared `MetaChipRow`.
    private var chipLine: some View {
        MetaChipRow(parts: typeAndGenreParts, trailingBadge: displayCertification,
                    font: .system(size: 26, weight: .regular),
                    leading: .provider(enrichment?.providerBadgeURL))
    }

    // year · runtime · ★ imdb  +  quality badges (PLACEHOLDER until addons provide them)
    private var metaLine: some View {
        HStack(spacing: 14) {
            Text(factsLine)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Theme.Color.primaryText)
            QualityBadges()
        }
    }

    /// The show hero's up-next episode (resume / next-to-watch). Pure algorithm lives in the view
    /// model; the live Trakt watch state is injected here.
    private var seriesUpNext: MetaDetailViewModel.UpNext? {
        model.upNext(
            progress: { trakt.progress(forKey: episodeKey($0)) },
            isWatched: { trakt.isWatched(type: typeID, imdb: metaID, season: $0.season, episode: $0.episode) }
        )
    }

    private func seasonEpisodeLabel(_ episode: Video) -> String { model.seasonEpisodeLabel(episode) }

    /// Play button label: episode-aware for series; Resume/Rewatch/Play for movies (Trakt state).
    private var playButtonTitle: String {
        if let upNext = seriesUpNext { return upNext.label }
        guard trakt.isSignedIn else { return "Play" }
        if trakt.progress(forKey: metaID) != nil { return "Resume" }
        if trakt.isWatched(type: typeID, imdb: metaID) { return "Rewatch" }
        return "Play"
    }

    /// Open the stream picker for what Play should play: a series' up-next episode (so stream addons,
    /// which key off the `tt…:S:E` episode id, return results), or the movie itself.
    private func startPlayback() {
        recordHistory()
        if let upNext = seriesUpNext {
            streamRequest = StreamRequest(
                type: typeID,
                contentID: upNext.video.id,
                title: meta.map { "\($0.name) — \(episodeLabel(upNext.video))" } ?? episodeLabel(upNext.video),
                backgroundURL: upNext.video.thumbnail ?? meta?.background,
                logoURL: meta?.logo
            )
        } else {
            streamRequest = StreamRequest(
                type: typeID,
                contentID: metaID,
                title: meta?.name ?? fallbackTitle,
                backgroundURL: meta?.background,
                logoURL: meta?.logo
            )
        }
    }

    // Reuses the shared hero buttons (HeroPlayButton / HeroCircleButton) from the home hero. Every button
    // reports `zone == .hero` while focused; moving focus down to the content flips the zone and drives
    // the full-viewport scroll. (Applying `.focused` externally works here as in HeroShelf's HeroActionRow.)
    private var actionButtons: some View {
        HStack(spacing: 18) {
            HeroPlayButton(title: playButtonTitle, icon: "play.fill") { startPlayback() }
                .focused($zone, equals: .hero)
            if trakt.isSignedIn {
                let inWatchlist = trakt.isInWatchlist(imdb: metaID)
                HeroCircleButton(
                    icon: inWatchlist ? "checkmark" : "plus",
                    accessibilityLabel: inWatchlist ? "Remove from Watchlist" : "Add to Watchlist"
                ) {
                    trakt.toggleWatchlist(type: typeID, imdb: metaID)
                }
                .focused($zone, equals: .hero)
                // Watched eye. For a show it marks the episode the Play pill resumes; for a movie it
                // marks the movie. No eye on a plain "Play" show (no specific episode to mark).
                if let upNext = seriesUpNext, upNext.marksEpisode {
                    let s = upNext.video.season ?? 0
                    let e = upNext.video.episode ?? 0
                    let watched = trakt.isWatched(type: typeID, imdb: metaID, season: s, episode: e)
                    HeroCircleButton(
                        icon: watched ? "eye.slash" : "eye",
                        accessibilityLabel: watched
                            ? "Mark \(seasonEpisodeLabel(upNext.video)) Unwatched"
                            : "Mark \(seasonEpisodeLabel(upNext.video)) Watched"
                    ) {
                        trakt.toggleEpisodeWatched(showIMDB: metaID, season: s, episode: e)
                    }
                    .focused($zone, equals: .hero)
                } else if typeID != "series" {
                    let watched = trakt.isWatched(type: typeID, imdb: metaID)
                    HeroCircleButton(
                        icon: watched ? "eye.slash" : "eye",
                        accessibilityLabel: watched ? "Mark as Unwatched" : "Mark as Watched"
                    ) {
                        trakt.toggleWatched(type: typeID, imdb: metaID)
                    }
                    .focused($zone, equals: .hero)
                }
            } else {
                HeroCircleButton(icon: "plus", accessibilityLabel: "Add to Up Next") { }
                    .focused($zone, equals: .hero)
            }
            HeroCircleButton(icon: "square.and.arrow.up", accessibilityLabel: "Share") { }
                .focused($zone, equals: .hero)
        }
        .padding(.top, 6)
    }

    /// Apple-style resume bar shown under the buttons when the up-next episode is mid-watch.
    @ViewBuilder
    private var resumeBar: some View {
        if let upNext = seriesUpNext, let progress = upNext.resumeProgress {
            HStack(spacing: 14) {
                ProgressBar(progress: progress)
                    .frame(width: 220, height: 5)

                Text("\(Int((progress * 100).rounded()))% · \(seasonEpisodeLabel(upNext.video))")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var creditsColumn: some View {
        let cast = displayCastNames
        let directors = displayDirectors
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

    // MARK: - Episodes (Season selector)

    private var seasons: [Int] { model.seasons }

    private var currentSeason: Int? { selectedSeason ?? seasons.first }

    private var allEpisodes: [Video] { model.allEpisodes }

    private func firstEpisodeID(of season: Int) -> String? {
        allEpisodes.first { ($0.season ?? 0) == season }?.id
    }

    /// Triggered when a season tab gains focus (or is clicked): highlight it and scroll the continuous
    /// episode strip to that season's first episode. No click required — focus alone drives it.
    private func selectSeason(_ season: Int, proxy: ScrollViewProxy) {
        selectedSeason = season
        guard let target = firstEpisodeID(of: season) else { return }
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

    @ViewBuilder
    private var episodesSection: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 18) {
                if seasons.count > 1 {
                    seasonSelector(proxy: proxy)
                } else {
                    DetailSectionHeader(title: "Episodes")
                }
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 28) {
                        ForEach(allEpisodes) { episode in
                            let info = episodeInfo[Enrichment.episodeKey(season: episode.season ?? 0, episode: episode.episode ?? 0)]
                            EpisodeCard(
                                thumbnailURL: info?.stillURL ?? episode.thumbnail.flatMap(URL.init(string:)),
                                episodeNumber: episode.episode ?? 0,
                                title: info?.title ?? episode.title ?? "Episode \(episode.episode ?? 0)",
                                overview: info?.overview ?? episode.overview,
                                dateText: airDate(episode.released),
                                durationText: episodeDurationText(episode, info: info),
                                ratingText: displayCertification,
                                progress: trakt.progress(forKey: episodeKey(episode)),
                                watched: trakt.isWatched(type: typeID, imdb: metaID, season: episode.season, episode: episode.episode),
                                isUpNext: seriesUpNext?.marksEpisode == true && episode.id == seriesUpNext?.video.id,
                                onFocusChange: { isFocused in
                                    if isFocused { episodeFocused(episode, proxy: proxy) }
                                },
                                onToggleWatched: trakt.isSignedIn ? {
                                    trakt.toggleEpisodeWatched(
                                        showIMDB: metaID,
                                        season: episode.season ?? 0,
                                        episode: episode.episode ?? 0
                                    )
                                } : nil
                            ) {
                                streamRequest = StreamRequest(
                                    type: typeID,
                                    contentID: episode.id,
                                    title: meta.map { "\($0.name) — \(episodeLabel(episode))" } ?? episodeLabel(episode),
                                    backgroundURL: episode.thumbnail ?? meta?.background,
                                    logoURL: meta?.logo
                                )
                            }
                            .id(episode.id)
                            // Single-season shows have no tabs, so the episode strip is the top content
                            // row — its cards report the content zone so Up from them returns to the hero.
                            .contentZone(seasons.count <= 1, $zone)
                        }
                    }
                    .padding(.horizontal, Theme.Detail.leftInset)
                    .padding(.vertical, 24)
                }
                .detailRowScroll()
                .focusSection()
            }
            // Focusing a season tab (not clicking) jumps the episode strip to that season.
            .onChange(of: focusedSeason) { _, newValue in
                guard let newValue else { return }
                selectSeason(newValue, proxy: proxy)
            }
            // On load, reveal the up-next episode: select its season and scroll the strip to it, so the
            // episode the hero Play targets is what you see first (instead of always S1, E1).
            .onChange(of: allEpisodes.count) { _, count in
                guard count > 0, !didRevealUpNext,
                      let upNext = seriesUpNext, upNext.marksEpisode else { return }
                didRevealUpNext = true
                selectedSeason = upNext.video.season
                withAnimation(.easeOut(duration: 0.35)) {
                    proxy.scrollTo(upNext.video.id, anchor: .leading)
                }
            }
            // Fetch TMDB episode info for the season in view, lazily — re-runs when the selected season
            // (or the title) changes. Scoped by metaID so a new title always refetches, never reusing
            // the previous title's season data. Bounds requests for long-running shows.
            .task(id: "\(metaID)|\(currentSeason ?? -1)") {
                await loadSeasonEnrichment(currentSeason)
            }
        }
    }

    /// Fetch and merge TMDB per-episode info + the season poster for one season. No-op when TMDB
    /// isn't configured or the season is nil / not yet known.
    private func loadSeasonEnrichment(_ season: Int?) async {
        guard let season, TMDBService.shared.isConfigured else { return }
        guard let result = await TMDBService.shared.seasonEnrichment(imdbID: metaID, season: season) else { return }
        episodeInfo.merge(result.episodes) { _, new in new }
        if let poster = result.posterURL { seasonPosters[season] = poster }
    }

    private func episodeDurationText(_ episode: Video, info: EpisodeEnrichment?) -> String {
        model.episodeDurationText(episode, info: info)
    }

    /// Horizontally scrollable so a long-running show's seasons stay reachable instead of being crushed
    /// to fit the screen. The focus engine auto-scrolls the strip to keep the focused tab on screen.
    private func seasonSelector(proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(seasons, id: \.self) { season in
                    Button { selectSeason(season, proxy: proxy) } label: {
                        Text("Season \(season)")
                            .font(.system(size: 26, weight: .semibold))
                            .padding(.horizontal, 22)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(SeasonTabStyle(isSelected: currentSeason == season))
                    .focused($focusedSeason, equals: season)
                    // Season tabs are the top content row for multi-season shows.
                    .contentZone(true, $zone)
                    .id("season-\(season)")
                }
            }
            .padding(.horizontal, Theme.Detail.leftInset)
            .padding(.vertical, 8)
        }
        .detailRowScroll()
        .focusSection()
    }

    /// Trakt playback/watched key for an episode: "showImdb:season:episode" (matches TraktService).
    private func episodeKey(_ episode: Video) -> String { model.episodeKey(episode) }

    private func episodeLabel(_ episode: Video) -> String { model.episodeLabel(episode) }

    // MARK: - Trailers

    /// Real TMDB trailers (YouTube) when enriched; otherwise the single placeholder card so the row —
    /// which is the top content row for movies — is never empty (the collapse relies on it).
    private var trailersSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            DetailSectionHeader(title: "Trailers")
            ScrollView(.horizontal) {
                HStack(spacing: 28) {
                    if let trailers = enrichment?.trailers, !trailers.isEmpty {
                        ForEach(trailers) { trailer in
                            TrailerCard(trailer: trailer) { openTrailer(trailer) }
                                // Movies have no episodes, so Trailers is the top content row.
                                .contentZone(seasons.isEmpty, $zone)
                        }
                    } else {
                        trailerCard
                            .contentZone(seasons.isEmpty, $zone)
                    }
                }
                .padding(.horizontal, Theme.Detail.leftInset)
                .padding(.vertical, 12)
            }
            .detailRowScroll()
            .focusSection()
        }
    }

    /// Hand a trailer off to the YouTube app. There is no public in-app YouTube playback on tvOS, so
    /// this is a best-effort deep link (a no-op if YouTube isn't installed to claim the scheme).
    private func openTrailer(_ trailer: Trailer) {
        guard let url = URL(string: "youtube://watch?v=\(trailer.youTubeKey)") else { return }
        openURL(url)
    }

    // One full-bleed 426×270 thumbnail (matches the reference's ~452×287 once the .card focus lift scales
    // it). A bottom-anchored dark gradient gives the overlaid text legibility while the image stays
    // faintly visible behind it — NOT an opaque caption bar. Title + "▶ 1m" sit low over the gradient.
    private var trailerCard: some View {
        Button { } label: {
            RemoteImage(
                url: (meta?.background ?? meta?.poster).flatMap(URL.init(string:)),
                targetSize: CGSize(width: 426, height: 270),
                contentMode: .fill
            ) {
                Color(white: 0.08)
            }
            .frame(width: 426, height: 270)
            .overlay(alignment: .bottom) {
                // Taller, darker fade so the text reads as clean neutral white/grey over any thumbnail
                // (a weak gradient lets the warm image tint the title); image still shows above the fade.
                LinearGradient(
                    colors: [.clear, .black.opacity(0.92)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 150)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(meta?.name ?? fallbackTitle) Trailer")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    HStack(spacing: 7) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("1m")   // PLACEHOLDER duration
                            .font(.system(size: 19))
                    }
                    .foregroundStyle(Color(white: 0.67))   // neutral light grey (~RGB 170), not image-tinted
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 13)
            }
            .frame(width: 426, height: 270)
        }
        .buttonStyle(.card)
    }

    // MARK: - Related

    private var relatedItems: [MetaPreview] { model.relatedItems }

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            DetailSectionHeader(title: "Related")
            ScrollView(.horizontal) {
                LazyHStack(spacing: 40) {
                    ForEach(relatedItems) { item in
                        ContentCard(meta: item, sizeOverride: CGSize(width: 261, height: 392)) {
                            openRelated(item)
                        }
                    }
                }
                .padding(.horizontal, Theme.Detail.leftInset)
                .padding(.vertical, 16)
            }
            .detailRowScroll()
            .focusSection()
        }
    }

    /// Navigate to a Related item. Genre-catalog items carry a real IMDB id and navigate directly;
    /// TMDB recommendation items carry an encoded TMDB ref, resolved to an IMDB id on select (one
    /// request) so the addon-backed detail screen can load it.
    private func openRelated(_ item: MetaPreview) {
        guard let ref = TMDBRef(encodedID: item.id) else {
            relatedSelection = item
            return
        }
        Task {
            guard let imdb = await TMDBService.shared.imdbID(for: ref) else { return }
            relatedSelection = MetaPreview(
                id: imdb, type: item.type, name: item.name,
                poster: item.poster, posterShape: nil, background: item.background,
                logo: nil, description: nil, releaseInfo: nil, imdbRating: nil, genres: nil
            )
        }
    }

    // MARK: - How to Watch

    /// Where the title is available to watch (TMDB/JustWatch, US), grouped by Stream / Rent / Buy.
    /// Purely informational — playback still happens via addons; this just tells the user where the
    /// title officially lives. Hidden entirely when TMDB has no availability for it.
    /// One card per provider, with its availabilities combined into the description (e.g. a provider
    /// offering both rent and buy shows once as "Rent/Buy"). Provider order follows first appearance
    /// across the priority-ordered groups (Stream → Rent → Buy …), so the labels join in that order.
    private var watchOptions: [WatchOption] { model.watchOptions }

    /// Three flexible columns; the grid grows downward and the page scroll view handles vertical paging.
    private var howToWatchColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 30), count: 3)
    }

    private var howToWatchSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            DetailSectionHeader(title: "How to Watch")
            LazyVGrid(columns: howToWatchColumns, spacing: 30) {
                ForEach(watchOptions) { option in
                    WatchProviderCard(provider: option.provider, availability: option.availability) {
                        if let link = enrichment?.watchLink { openURL(link) }
                    }
                }
            }
            .padding(.horizontal, Theme.Detail.leftInset)
        }
        .focusSection()
    }

    // MARK: - About

    /// Shared geometry for the frosted info cards (About + Information). One column width, so the About
    /// card and the Information column read as the same panel.
    private let infoCardWidth: CGFloat = 565

    /// Left guide for the About + Information block: the section headers and the card *text* align here
    /// (matching the reference at ≈ 80pt). The frosted cards' panels bleed `infoCardPadding` further left
    /// (to ≈ 56pt), so the card edge sits left of the header while the text aligns with it.
    private let infoBlockInset: CGFloat = 80
    private let infoCardPadding: CGFloat = 24

    /// Muted rail header (like "Cast & Crew") + a frosted card with the title, genre, and synopsis.
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            DetailSectionHeader(title: "About", leadingInset: infoBlockInset)
            aboutCard
                .padding(.leading, infoBlockInset)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    private var aboutCard: some View {
        Button { } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(meta?.name ?? fallbackTitle)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let genre = displayGenres.first, !genre.isEmpty {
                    Text(genre)
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.Color.secondaryText)
                        .padding(.top, 4)
                }
                if let description = displayDescription, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 24))
                        .foregroundStyle(Color(white: 0.93))   // ≈ #EDEDED
                        .lineSpacing(4)
                        .padding(.top, 18)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: infoCardWidth - infoCardPadding * 2, alignment: .leading)
            // Real leading padding (no bleed): `.card` clips to the label bounds, which would chop a
            // negative-leading bleed and squash the inset, so the leading is a true padding here.
            .frostedInfoCard(padding: 22, bleedLeading: false)
        }
        .buttonStyle(.card)
    }

    // MARK: - Information (static row: Information / Languages / Accessibility)

    // PLACEHOLDER strings — language/subtitle tracks & accessibility flags come from the stream/addon,
    // not basic meta.
    private let audioLanguages = "English (Dolby Atmos, Dolby 5.1, AAC, AD), French (Canada) (Dolby 5.1, AAC, AD), French (France) (Dolby 5.1, AAC, AD), German (Dolby 5.1, AAC, AD), Italian (Dolby 5.1, AAC, AD), Japanese (Dolby 5.1, AAC, AD), Portuguese (Brazil) (Dolby 5.1, AAC, AD), Spanish"
    private let subtitleLanguages = "English (CC, SDH), Arabic (SDH), Bulgarian (SDH), Cantonese, Traditional (SDH), Chinese, Simplified (SDH), Chinese, Traditional (SDH), Czech (SDH), Danish (SDH), Dutch (SDH), Estonian (SDH), Finnish (SDH), French (Canada) (SDH), French (France) (SDH), German (SDH), Greek (SDH), Hungarian (SDH), Italian (SDH), Japanese (SDH)"
    private let sdhDescription = "Subtitles for the deaf and hard of hearing (SDH) refer to subtitles in the original language with the addition of relevant non-dialogue information."
    private let adDescription = "Audio descriptions (AD) refer to a narration track describing what is happening on screen, to provide context for those who are blind or have low vision."

    /// The static row: Information / Languages / Accessibility side by side. Information is a frosted
    /// card; Languages and Accessibility are plain text (with the inline "MORE" cue where truncated).
    private var informationSection: some View {
        HStack(alignment: .top, spacing: 40) {
            informationColumn
            languagesColumn
            accessibilityColumn
        }
        // Leading at the block guide; trailing tuned so the three equal columns land on the reference
        // guides (text at ≈ 80 / 686 / 1292pt).
        .padding(.leading, infoBlockInset)
        .padding(.trailing, 62)
        // Generous bottom region so the focus engine's auto-scroll never scrolls past the footer; below
        // it the page's own warm blurred gradient shows through (no dark shelf — one continuous gradient).
        .padding(.bottom, 600)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .top) { footerPanel }
        .padding(.top, footerTopGap)   // About card → header gap, matched to the reference (≈90pt)
        .focusSection()
    }

    private let footerTopGap: CGFloat = 32

    /// A dark translucent scrim behind the footer so it reads darker than the rest of the page, fading
    /// out toward the bottom back to the bare backdrop. Bleeds up into the gap above the headers.
    private var footerPanel: some View {
        Rectangle()
            .fill(.black.opacity(0.42))
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .white, location: 0.0),
                        .init(color: .white, location: 0.42),
                        .init(color: .clear, location: 0.82)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .padding(.top, -footerPanelTopBleed)
            .allowsHitTesting(false)
    }

    private let footerPanelTopBleed: CGFloat = 30

    private var informationColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            InfoColumnHeader(title: "Information")
            InfoColumnCard {
                if let year = meta?.releaseInfo, !year.isEmpty {
                    InfoPair(label: "Released", value: year)
                }
                if let runtime = displayRuntime {
                    InfoPair(label: "Run Time", value: runtime)
                }
                InfoPair(label: "Rated", value: displayCertification)
                if let status = enrichment?.status, !status.isEmpty {
                    InfoPair(label: "Status", value: status)
                }
                if !displayGenres.isEmpty {
                    InfoPair(label: "Genre", value: displayGenres.joined(separator: ", "))
                }
                InfoPair(label: "Content Advisories", value: "Violence, Language")
                InfoPair(label: "Regions of Origin", value: enrichment?.country ?? "United States")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var languagesColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            InfoColumnHeader(title: "Languages")
            InfoColumnCard(spacing: 22) {
                InfoPair(label: "Original Audio", value: enrichment?.language ?? "English")
                InfoPair(label: "Audio", value: audioLanguages, lineLimit: 4)
                InfoPair(label: "Subtitles", value: subtitleLanguages, lineLimit: 5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessibilityColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            InfoColumnHeader(title: "Accessibility")
            InfoColumnCard(spacing: 26) {
                AccessibilityItem(badge: "SDH", description: sdhDescription)
                AccessibilityItem(badge: "AD", description: adDescription)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Cast & Crew

    /// Cast & Crew row. With TMDB enrichment each chip shows a headshot + character/role; without it,
    /// falls back to the addon's name-only cast + director (initials avatars).
    private var castSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            DetailSectionHeader(title: "Cast & Crew")
            ScrollView(.horizontal) {
                LazyHStack(spacing: 28) {
                    ForEach(creditEntries) { entry in
                        Button { } label: {
                            CastChip(name: entry.name, role: entry.role, imageURL: entry.imageURL)
                        }
                        .buttonStyle(CastChipStyle())
                    }
                }
                .padding(.horizontal, Theme.Detail.leftInset)
                .padding(.vertical, 16)
            }
            .detailRowScroll()
            .focusSection()
        }
    }

    // MARK: - Helpers (delegate to MetaDetailViewModel)

    private var typeAndGenreParts: [String] { model.typeAndGenreParts }
    private var factsLine: String { model.factsLine }

    private var displayLogoURL: URL? { model.displayLogoURL }
    private var displayDescription: String? { model.displayDescription }
    private var displayGenres: [String] { model.displayGenres }
    private var displayCertification: String { model.displayCertification }
    private var displayRuntime: String? { model.displayRuntime }
    private var displayCastNames: [String] { model.displayCastNames }
    private var displayDirectors: [String] { model.displayDirectors }
    private var creditEntries: [CreditEntry] { model.creditEntries }

    private func airDate(_ released: String?) -> String? { model.airDate(released) }

    private func recordHistory() {
        WatchHistory.shared.record(
            typeID: typeID,
            metaID: metaID,
            name: meta?.name ?? fallbackTitle,
            poster: meta?.poster,
            background: meta?.background,
            logo: meta?.logo
        )
    }

    // MARK: - Loading

    private func load() async {
        // Reset per-title TMDB state so a reused view (metaID change) never shows the previous
        // title's enrichment or episode data while the new title loads.
        enrichment = nil
        episodeInfo = [:]
        seasonPosters = [:]
        didRevealUpNext = false
        if let previewMeta {                       // sample/preview path — no networking
            meta = previewMeta
            status = .loaded
            return
        }
        status = .loading
        for addon in registry.enabledAddons {
            do {
                let response = try await StremioClient.shared.meta(
                    baseURL: addon.baseURL,
                    type: typeID,
                    id: metaID
                )
                meta = response.meta
                status = .loaded
                // Related (genre catalog) and TMDB enrichment run concurrently; neither blocks the
                // already-displayed base meta. Enrichment is best-effort — `enrich` returns nil when
                // TMDB isn't configured, the id isn't an IMDB id, or there's no match.
                async let relatedTask: Void = loadRelated()
                async let enrichTask = TMDBService.shared.enrich(stremioType: typeID, imdbID: metaID)
                _ = await relatedTask
                enrichment = await enrichTask
                return
            } catch {
                continue
            }
        }
        status = .failed
    }

    private func loadRelated() async {
        guard let m = meta else { return }
        let firstGenre = m.genres?.first
        for addon in registry.enabledAddons {
            let catalogs = addon.manifest.catalogs ?? []
            guard let catalog = catalogs.first(where: { $0.type == typeID }) else { continue }
            let extra = firstGenre.map { ["genre": $0] } ?? [:]
            do {
                let response = try await StremioClient.shared.catalog(
                    baseURL: addon.baseURL,
                    type: typeID,
                    id: catalog.id,
                    extra: extra
                )
                let filtered = response.metas.filter { $0.id != metaID }
                related = Array(filtered.prefix(12))
                if !related.isEmpty { return }
            } catch {
                continue
            }
        }
    }
}

// MARK: - Preview (PROPELLER sample — matches the reference clip; all values flow through the model)

#Preview("Detail — PROPELLER") {
    // Sample/preview data only. The film and every value tied to it are what shows in the reference
    // video; the running app feeds real dynamic data through the same model.
    let sample = Meta(
        id: "tt-propeller",
        type: "movie",
        name: "Propeller One-Way Night Coach",
        poster: nil,
        background: nil,
        logo: nil,
        description: "During the golden age of aviation, a young airplane enthusiast and his mother "
            + "embark on a cross-country journey to Hollywood—and their simple flight transforms into "
            + "the trip of a lifetime. A film by John Travolta.",
        releaseInfo: "2026",
        runtime: "1 hr",
        imdbRating: nil,
        genres: ["Drama"],
        cast: ["Clark Shotwell", "Kelly Eviston-Quinnett", "Ella Travolta"],
        director: ["John Travolta"],
        videos: nil
    )
    return NavigationStack {
        MetaDetailView(
            typeID: "movie",
            metaID: "tt-propeller",
            fallbackTitle: "Propeller One-Way Night Coach",
            previewMeta: sample
        )
    }
}
