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
    @State private var status: LoadStatus = .loading
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

    struct StreamRequest: Identifiable, Hashable {
        let type: String
        let contentID: String
        let title: String
        var backgroundURL: String? = nil
        var logoURL: String? = nil
        var id: String { "\(type):\(contentID)" }
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
                        if !related.isEmpty {
                            relatedSection.id("related")
                        }
                        howToWatchSection
                        if let cast = meta?.cast, !cast.isEmpty {
                            castSection(cast: cast)
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
        .fullScreenCover(item: $streamRequest) { req in
            StreamPickerView(
                type: req.type,
                contentID: req.contentID,
                title: req.title,
                backgroundURL: req.backgroundURL,
                logoURL: req.logoURL
            )
        }
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

    private var backdropURL: URL? {
        (meta?.background ?? meta?.poster).flatMap(URL.init(string:))
    }

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
                .padding(.trailing, 74)

            VStack(alignment: .leading, spacing: 16) {   // tighter rhythm pulls the upper stack down ~25 px
                titleView
                chipLine
                if let description = meta?.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 27))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineSpacing(6)               // ≈ line-height 1.25 at 27 pt
                        .lineLimit(4)
                        .frame(maxWidth: 660, alignment: .leading)   // wraps at ≈ x 746 from the x 86 guide
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
        if let logo = meta?.logo, let url = URL(string: logo) {
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
        if let logo = meta?.logo, let url = URL(string: logo) {
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

    // type · genre · genre  +  content-rating box (rating box is a PLACEHOLDER until addons provide it).
    // Reuses the shared `MetaChipRow` from the home hero.
    private var chipLine: some View {
        MetaChipRow(parts: typeAndGenreParts, trailingBadge: ratingPlaceholder,
                    font: .system(size: 26, weight: .regular))
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

    /// The episode the hero Play targets for a series, plus its button label (Apple TV+ style — the
    /// button names the episode). nil for movies.
    private struct UpNext {
        let video: Video
        let label: String
        let resumeProgress: Double?   // non-nil while this episode is mid-watch on Trakt
        let marksEpisode: Bool        // true for resume / next-unwatched; false for the "Rewatch" fallback
    }

    /// The show hero's episode: the last played episode if it isn't finished (resume), otherwise the
    /// next episode to watch — the one right after your furthest-watched episode. We use the *furthest*
    /// watched (not the earliest gap), so an old skipped episode can't drag the hero backward.
    private var seriesUpNext: UpNext? {
        guard typeID == "series" else { return nil }
        let eps = allEpisodes
        guard !eps.isEmpty else { return nil }

        // 1. Last played but not finished → resume it.
        if let inProgress = eps.last(where: { trakt.progress(forKey: episodeKey($0)) != nil }) {
            return UpNext(
                video: inProgress,
                label: "Resume \(seasonEpisodeLabel(inProgress))",
                resumeProgress: trakt.progress(forKey: episodeKey(inProgress)),
                marksEpisode: true
            )
        }
        // 2. Next to watch → the episode right after the furthest-watched one.
        if let lastWatchedIdx = eps.lastIndex(where: {
            trakt.isWatched(type: typeID, imdb: metaID, season: $0.season, episode: $0.episode)
        }) {
            let nextIdx = eps.index(after: lastWatchedIdx)
            if nextIdx < eps.count {
                let next = eps[nextIdx]
                return UpNext(video: next, label: "Play \(seasonEpisodeLabel(next))", resumeProgress: nil, marksEpisode: true)
            }
            // Furthest-watched is the final episode → nothing left to watch next.
            return UpNext(video: eps[0], label: "Play", resumeProgress: nil, marksEpisode: false)
        }
        // 3. Nothing watched yet → the next to watch is the first episode.
        return UpNext(video: eps[0], label: "Play \(seasonEpisodeLabel(eps[0]))", resumeProgress: nil, marksEpisode: true)
    }

    private func seasonEpisodeLabel(_ episode: Video) -> String {
        "S\(episode.season ?? 0), E\(episode.episode ?? 0)"
    }

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
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.3))
                        Capsule().fill(.white).frame(width: geo.size.width * max(0, min(1, progress)))
                    }
                }
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
        let cast = meta?.cast ?? []
        let directors = meta?.director ?? []
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
            .frame(maxWidth: 360, alignment: .leading)
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

    private var seasons: [Int] {
        guard let videos = meta?.videos else { return [] }
        return Array(Set(videos.compactMap { $0.season }).filter { $0 > 0 }).sorted()
    }

    private var currentSeason: Int? { selectedSeason ?? seasons.first }

    /// Every episode from every season in one continuous list, ordered by season then episode.
    /// Apple TV's episode row is a single horizontal strip spanning all seasons — so moving right off
    /// the last episode of a season flows straight into the first episode of the next, with no per-season
    /// filtering. The season selector above is a "jump to" control rather than a filter.
    private var allEpisodes: [Video] {
        (meta?.videos ?? [])
            .filter { ($0.season ?? 0) > 0 }
            .sorted {
                let s0 = $0.season ?? 0, s1 = $1.season ?? 0
                if s0 != s1 { return s0 < s1 }
                return ($0.episode ?? 0) < ($1.episode ?? 0)
            }
    }

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
                            EpisodeCard(
                                thumbnailURL: episode.thumbnail.flatMap(URL.init(string:)),
                                episodeNumber: episode.episode ?? 0,
                                title: episode.title ?? "Episode \(episode.episode ?? 0)",
                                overview: episode.overview,
                                dateText: airDate(episode.released),
                                durationText: episodeDuration(episode),   // PLACEHOLDER duration
                                ratingText: ratingPlaceholder,             // PLACEHOLDER rating
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
        }
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

    // PLACEHOLDER — per-episode runtime isn't in Stremio's basic meta; derive a stable, varied value
    // per episode so the row looks like Apple's (38m / 47m / 1h 2m) until an addon supplies real data.
    private func episodeDuration(_ episode: Video) -> String {
        let n = episode.episode ?? 1
        let minutes = 42 + (n * 11) % 28
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    /// Trakt playback/watched key for an episode: "showImdb:season:episode" (matches TraktService).
    private func episodeKey(_ episode: Video) -> String {
        "\(metaID):\(episode.season ?? 0):\(episode.episode ?? 0)"
    }

    private func episodeLabel(_ episode: Video) -> String {
        let s = episode.season ?? 0
        let e = episode.episode ?? 0
        let prefix = "S\(s)·E\(e)"
        if let title = episode.title, !title.isEmpty {
            return "\(prefix) — \(title)"
        }
        return prefix
    }

    // MARK: - Trailers (PLACEHOLDER — replace when an addon provides trailer sources)

    private var trailersSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            DetailSectionHeader(title: "Trailers")
            ScrollView(.horizontal) {
                HStack(spacing: 28) {
                    trailerCard
                        // Movies have no episodes, so Trailers is the top content row.
                        .contentZone(seasons.isEmpty, $zone)
                }
                .padding(.horizontal, Theme.Detail.leftInset)
                .padding(.vertical, 12)
            }
            .detailRowScroll()
            .focusSection()
        }
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

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            DetailSectionHeader(title: "Related")
            ScrollView(.horizontal) {
                LazyHStack(spacing: 40) {
                    ForEach(related) { item in
                        ContentCard(meta: item, sizeOverride: CGSize(width: 261, height: 392)) {
                            relatedSelection = item
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

    // MARK: - How to Watch (PLACEHOLDER — provider info will come from addons)

    private var howToWatchSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            DetailSectionHeader(title: "How to Watch")
            Button {
                recordHistory()
                streamRequest = StreamRequest(
                    type: typeID,
                    contentID: metaID,
                    title: meta?.name ?? fallbackTitle,
                    backgroundURL: meta?.background,
                    logoURL: meta?.logo
                )
            } label: {
                HStack(spacing: 16) {
                    HomeTVSourceBadge()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Play with Infuse")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Theme.Color.primaryText)
                        Text("Opens the stream in your default player")
                            .font(.caption)
                            .foregroundStyle(Theme.Color.secondaryText)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.Color.secondaryText)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .frame(maxWidth: 760, alignment: .leading)
            }
            .buttonStyle(.card)
            .padding(.horizontal, Theme.Detail.leftInset)
        }
         .frame(maxWidth: .infinity, alignment: .leading)
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
                if let genre = meta?.genres?.first, !genre.isEmpty {
                    Text(genre)
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.Color.secondaryText)
                        .padding(.top, 4)
                }
                if let description = meta?.description, !description.isEmpty {
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
        .focusSection()
    }

    private var informationColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            InfoColumnHeader(title: "Information")
            InfoColumnCard {
                if let year = meta?.releaseInfo, !year.isEmpty {
                    InfoPair(label: "Released", value: year)
                }
                if let runtime = meta?.runtime, !runtime.isEmpty {
                    InfoPair(label: "Run Time", value: runtime)
                }
                InfoPair(label: "Rated", value: ratingPlaceholder)
                if let genres = meta?.genres, !genres.isEmpty {
                    InfoPair(label: "Genre", value: genres.joined(separator: ", "))
                }
                InfoPair(label: "Content Advisories", value: "Violence, Language")
                InfoPair(label: "Regions of Origin", value: "United States")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var languagesColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            InfoColumnHeader(title: "Languages")
            InfoColumnCard(spacing: 22) {
                InfoPair(label: "Original Audio", value: "English")
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

    private func castSection(cast: [String]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            DetailSectionHeader(title: "Cast & Crew")
            ScrollView(.horizontal) {
                LazyHStack(spacing: 28) {
                    ForEach(Array(cast.prefix(12).enumerated()), id: \.offset) { _, name in
                        Button { } label: {
                            CastChip(name: name, role: "Cast")   // role is a PLACEHOLDER (Stremio gives names only)
                        }
                        .buttonStyle(CastChipStyle())
                    }
                    ForEach(Array((meta?.director ?? []).enumerated()), id: \.offset) { _, name in
                        Button { } label: {
                            CastChip(name: name, role: "Director")
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

    // MARK: - Helpers

    private var typeAndGenreParts: [String] {
        var parts = [typeLabel(typeID)]
        if let genres = meta?.genres, !genres.isEmpty {
            parts.append(contentsOf: genres.prefix(2))
        }
        return parts
    }

    private func typeLabel(_ type: String) -> String {
        switch type {
        case "movie": "Movie"
        case "series": "TV Show"
        case "channel": "Channel"
        case "tv": "Live TV"
        default: type.capitalized
        }
    }

    // PLACEHOLDER — content rating isn't in Stremio's basic meta; addons will supply it.
    private var ratingPlaceholder: String {
        typeID == "series" ? "TV-MA" : "PG-13"
    }

    private var factsLine: String {
        var parts: [String] = []
        if let year = meta?.releaseInfo, !year.isEmpty { parts.append(year) }
        if let runtime = meta?.runtime, !runtime.isEmpty { parts.append(runtime) }
        if let rating = meta?.imdbRating, !rating.isEmpty { parts.append("★ \(rating)") }
        return parts.joined(separator: " · ")
    }

    private func airDate(_ released: String?) -> String? {
        guard let released, !released.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: released) ?? ISO8601DateFormatter().date(from: released)
        guard let date else { return String(released.prefix(10)) }
        let out = DateFormatter()
        out.dateFormat = "MMM d, yyyy"
        return out.string(from: date)
    }

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
                await loadRelated()
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

// MARK: - Section header (dark background, Apple Title Case)

private struct DetailSectionHeader: View {
    let title: String
    /// Left guide for the header. Defaults to the global content margin; the About/Information block
    /// passes its own (slightly tighter) guide so the header aligns with that block's card text.
    var leadingInset: CGFloat = Theme.Detail.leftInset
    /// Browse-chrome opacity: section labels belong to State B. They're hidden in State A (so the bare
    /// trailer card peeks at the bottom with no header above it) and fade in with the collapse.
    @Environment(\.detailChromeOpacity) private var chromeOpacity

    var body: some View {
        // The card/posters rise with the content without fading; only this label fades in.
        Text(title)
            .font(.system(size: 30, weight: .semibold))
            // Opaque secondary grey (~RGB 153) so it reads consistently dim — white@opacity alpha-blends
            // with the bright blurred backdrop and comes out too light.
            .foregroundStyle(Color(white: 0.6))
            .padding(.leading, leadingInset)
            .opacity(chromeOpacity)
    }
}

private struct DetailChromeOpacityKey: EnvironmentKey {
    static let defaultValue: Double = 1
}

extension EnvironmentValues {
    /// 0 in State A → 1 in State B; drives the browse-chrome (section headers) fade-in.
    var detailChromeOpacity: Double {
        get { self[DetailChromeOpacityKey.self] }
        set { self[DetailChromeOpacityKey.self] = newValue }
    }
}

// MARK: - Hero chip badges

/// PLACEHOLDER capability chips — real values (4K/Dolby/CC/SDH/AD) will come from addons. Chip styles
/// per the spec: 4K is a filled light chip with dark text; the rest are outlined (white @ 0.55).
private struct QualityBadges: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("4K")
                .font(.system(size: 19, weight: .semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(red: 0.85, green: 0.85, blue: 0.85))
                )
                .foregroundStyle(.black.opacity(0.85))
            ForEach(["CC", "SDH", "AD"], id: \.self) { badge in
                OutlinedBadge(text: badge)
            }
        }
    }
}

/// The shared outlined metadata chip (white stroke, light text) used by the hero capability chips and
/// the Accessibility SDH / AD badges, so both read identically.
struct OutlinedBadge: View {
    let text: String
    var tint: Color = .white.opacity(0.9)

    var body: some View {
        Text(text)
            .font(.system(size: 19, weight: .medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(tint.opacity(0.65), lineWidth: 1)
            )
            .foregroundStyle(tint)
    }
}

// MARK: - Season selector tab

private struct SeasonTabStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, isSelected: isSelected)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let isSelected: Bool
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .foregroundStyle(foreground)
                .background(
                    Capsule(style: .continuous).fill(fill)
                )
                .scaleEffect(configuration.isPressed ? 0.97 : (isFocused ? 1.05 : 1.0))
                .animation(.easeOut(duration: 0.18), value: isFocused)
        }

        private var foreground: Color {
            if isFocused { return .black }
            return isSelected ? Theme.Color.primaryText : Theme.Color.tertiaryText
        }

        private var fill: Color {
            if isFocused { return Theme.Color.primaryText }
            return isSelected ? Theme.Color.primaryText.opacity(0.18) : .clear
        }
    }
}

// MARK: - Episode card

/// An episode entry = TWO separate stacked elements, matching Apple:
///  • the thumbnail is its own focusable button with the standard tvOS card focus (lift + specular);
///  • the description sits in its own translucent container that does NOT change on focus.
private struct EpisodeCard: View {
    let thumbnailURL: URL?
    let episodeNumber: Int
    let title: String
    let overview: String?
    let dateText: String?
    let durationText: String
    let ratingText: String
    /// Watch progress (0–1) from Trakt playback. `nil` = not in progress, so no play indicator is
    /// shown (matches Apple: the play glyph only appears on an episode you've already started).
    var progress: Double? = nil
    /// Whether this episode is marked watched on Trakt — shows a checkmark badge.
    var watched: Bool = false
    /// Whether this is the episode the hero Play will play — shows an "Up Next" badge.
    var isUpNext: Bool = false
    /// Reports focus gain/loss to the parent so the season selector can track which season the
    /// in-view episode belongs to as you scroll across the continuous strip.
    var onFocusChange: (Bool) -> Void = { _ in }
    /// Secondary action (long-press): toggle this episode's watched state. Hidden when nil.
    var onToggleWatched: (() -> Void)? = nil
    let action: () -> Void

    @FocusState private var focused: Bool

    // Sized so 4 cards are fully visible with the 5th peeking (88pt gutter + 4×400 + 3×28 = 1772,
    // 5th starts at 1800 within the 1920pt width) — matches Apple TV's episode row.
    private let width: CGFloat = 400
    private let imageHeight: CGFloat = 225

    var body: some View {
        // When focused the image lifts/scales (.card); open the gap enough that the lifted image
        // clears the description (rather than overlapping it), animating in step with the card.
        VStack(alignment: .leading, spacing: focused ? 28 : 8) {
            imageButton
            descriptionBox
        }
        .frame(width: width)
        .animation(.easeOut(duration: 0.25), value: focused)
        .onChange(of: focused) { _, isFocused in onFocusChange(isFocused) }
    }

    private var imageButton: some View {
        Button(action: action) {
            RemoteImage(url: thumbnailURL, targetSize: CGSize(width: width, height: imageHeight), contentMode: .fill) {
                Color(white: 0.1)
            }
            .frame(width: width, height: imageHeight)
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 90)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) { durationOverlay }
            .overlay(alignment: .topTrailing) { watchedBadge }
            .overlay(alignment: .topLeading) { upNextBadge }
        }
        .buttonStyle(.card)
        .focused($focused)
        // Long-press (select hold) reveals the watched toggle — click still plays.
        .contextMenu {
            if let onToggleWatched {
                Button {
                    onToggleWatched()
                } label: {
                    Label(watched ? "Mark as Unwatched" : "Mark as Watched",
                          systemImage: watched ? "eye.slash" : "eye")
                }
            }
        }
    }

    @ViewBuilder
    private var upNextBadge: some View {
        if isUpNext {
            Text("UP NEXT")
                .font(.system(size: 12, weight: .heavy))
                .tracking(0.5)
                .foregroundStyle(.black)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(.white))
                .padding(10)
        }
    }

    @ViewBuilder
    private var watchedBadge: some View {
        if watched {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
                .padding(10)
        }
    }

    private var durationOverlay: some View {
        HStack(spacing: 8) {
            if let progress {
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                Capsule()
                    .fill(.white.opacity(0.35))
                    .frame(width: 90, height: 4)
                    .overlay(alignment: .leading) {
                        Capsule().fill(.white).frame(width: 90 * progress, height: 4)
                    }
            }
            Text(durationText)   // PLACEHOLDER duration
                .font(.system(size: 15, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.leading, 14)
        .padding(.bottom, 10)
    }

    private var descriptionBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EPISODE \(episodeNumber)")
                .font(.system(size: 14, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.55))
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            if let overview, !overview.isEmpty {
                Text(overview)
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.7))
                    // Always reserve two lines so the block height is identical focused/unfocused
                    // (no reflow from one line to two when focus toggles).
                    .lineLimit(2, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                if let dateText {
                    Text(dateText)
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Text(ratingText)
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(.white.opacity(0.5), lineWidth: 1.2)
                    )
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: width, alignment: .topLeading)
        // Translucent container only on the selected (focused) episode; others show plain text.
        .background(focused ? Color.black.opacity(0.3) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.easeOut(duration: 0.18), value: focused)
    }
}

// MARK: - Information block pieces

/// The one reusable frosted-panel look shared by the About card and the Information card: a
/// translucent `.ultraThinMaterial` fill (so the warm page gradient shows through), 22 pt corners,
/// and 24 pt internal padding. White content reads cleanly over it.
///
/// The content's *leading* edge stays at the layout guide (so it aligns with the section header), and
/// the frosted panel bleeds 24 pt further left as a background-only inset — matching the reference,
/// where the card edge sits left of the header while the card text aligns with it.
extension View {
    /// `padding` insets the content from the panel edge uniformly. Vertical + trailing are always real
    /// padding. When `bleedLeading` is true (default), the leading is supplied by the panel's
    /// negative-leading bleed so the text leading stays aligned with the section header while the panel
    /// edge sits `padding` further left. When false, the leading is a true padding (needed under a
    /// clipping style like `.card`, which would otherwise chop the bleed off).
    /// `showsBackground` toggles only the frosted panel — the padding is applied either way, so a card
    /// can appear/disappear on focus without the content shifting (used by the focus-aware info columns,
    /// which show the panel only while focused).
    func frostedInfoCard(padding: CGFloat = 24, bleedLeading: Bool = true, showsBackground: Bool = true) -> some View {
        self.padding(.vertical, padding)
            .padding(.trailing, padding)
            .padding(.leading, bleedLeading ? 0 : padding)
            .background {
                // Material gives the frost/blur; the white tint lifts it to the reference's lighter
                // translucent panel (≈ rgb 107,95,94) so it reads clearly over a dark backdrop, not
                // just over a bright one. Driven by opacity (not an `if`) so it can crossfade in/out on
                // focus rather than popping — the panel is otherwise always laid out.
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(.white.opacity(0.10))
                    )
                    .padding(.leading, bleedLeading ? -padding : 0)   // panel bleeds left of the text/header guide
                    .opacity(showsBackground ? 1 : 0)
            }
    }
}

/// Colour scheme for the Information block. The in-page sections render on the dark/translucent
/// background (white text); the centered expand overlay renders on a light frosted card (dark text) —
/// the inverse.
struct InfoPalette {
    let title: Color
    let label: Color
    let value: Color
    let more: Color
    let badge: Color
    let accessory: Color

    static let onDark = InfoPalette(
        title: .white,
        label: .white.opacity(0.5),
        value: Color(red: 0.929, green: 0.894, blue: 0.886),   // ≈ #EDE4E2
        more: .white,
        badge: .white.opacity(0.85),
        accessory: .white.opacity(0.78)
    )
    static let onLight = InfoPalette(
        title: .black.opacity(0.9),
        label: .black.opacity(0.5),
        value: .black.opacity(0.82),
        more: .black.opacity(0.9),
        badge: .black.opacity(0.7),
        accessory: .black.opacity(0.7)
    )
}

private struct InfoColumnHeader: View {
    let title: String
    var palette: InfoPalette = .onDark

    var body: some View {
        // Large bold column header (Information / Languages / Accessibility) — distinct from the smaller
        // muted rail headers ("About", "Cast & Crew").
        Text(title)
            .font(.system(size: 43, weight: .bold))
            .foregroundStyle(palette.title)
            .padding(.bottom, 4)
    }
}

/// A label-over-value pair, e.g. "Released" / "2026". Long values tail-truncate to `lineLimit` with a
/// plain bold inline "MORE" cue (only in the in-page resting state; the overlay shows the full value).
private struct InfoPair: View {
    let label: String
    let value: String
    var lineLimit: Int? = nil
    var palette: InfoPalette = .onDark

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 20))
                .foregroundStyle(palette.label)
            InfoValueText(value: value, lineLimit: lineLimit, palette: palette)
        }
    }
}

/// The value text. When it overflows `lineLimit`, CoreText wraps it so the last visible line ends with an
/// ellipsis followed *inline* by a plain bold uppercase "MORE" cue (no box, no fill) — e.g.
/// "…Japanese (Dolby 5.1, AA… MORE". With no `lineLimit` (the overlay) it shows the full value.
private struct InfoValueText: View {
    let value: String
    let lineLimit: Int?
    var fontSize: CGFloat = 24
    var palette: InfoPalette = .onDark

    @State private var width: CGFloat = 0
    /// Cached CoreText truncation, recomputed only when its inputs (width, value) change — not on every
    /// body evaluation (focus animations re-render the info columns repeatedly), so CTTypesetter work
    /// stays off the render path.
    @State private var wrapped: (body: AttributedString, truncated: Bool)?

    private var moreReserve: CGFloat { fontSize * 4 + 24 }
    private let lineSpacing: CGFloat = 4

    var body: some View {
        content
            .lineSpacing(lineSpacing)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                GeometryReader { _ in
                    Color.clear.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                }
            }
            .onChange(of: width) { recomputeWrap() }
            .onChange(of: value) { recomputeWrap() }
    }

    /// Rebuilds the cached truncation for the current inputs. Cleared to `nil` when there's nothing to
    /// truncate (no line limit or no measured width yet), in which case `content` shows the full value.
    private func recomputeWrap() {
        guard let lineLimit, width > 1 else { wrapped = nil; return }
        wrapped = InfoTextWrap.truncate(value, fontSize: fontSize, width: width,
                                        lineLimit: lineLimit, reserve: moreReserve,
                                        palette: palette)
    }

    @ViewBuilder
    private var content: some View {
        if let wrapped, wrapped.truncated {
            Text(wrapped.body)   // pre-wrapped lines, the last ending with "…", + inline bold "MORE"
        } else {
            Text(value)
                .font(.system(size: fontSize))
                .foregroundStyle(palette.value)
                .lineLimit(lineLimit)
        }
    }
}

/// CoreText line-wrapping helper: breaks a string into rendered lines at a given width and, past a line
/// limit, builds an AttributedString of those lines whose last line ends with "…" followed by a bold
/// inline "MORE" cue. CoreText/Foundation only — no UIKit.
private enum InfoTextWrap {
    private static func systemFont(_ size: CGFloat) -> CTFont {
        CTFontCreateUIFontForLanguage(.system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    private static func lineBreaks(_ string: String, font: CTFont, width: CGFloat) -> [Int] {
        let key = NSAttributedString.Key(kCTFontAttributeName as String)
        let attr = NSAttributedString(string: string, attributes: [key: font])
        let typesetter = CTTypesetterCreateWithAttributedString(attr)
        let total = (string as NSString).length
        var breaks: [Int] = []
        var start = 0
        var guardCount = 0
        while start < total, guardCount < 400 {
            guardCount += 1
            let n = CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
            if n <= 0 { break }
            start += n
            breaks.append(start)
        }
        return breaks
    }

    static func truncate(_ string: String, fontSize: CGFloat, width: CGFloat,
                         lineLimit: Int, reserve: CGFloat,
                         palette: InfoPalette = .onDark)
        -> (body: AttributedString, truncated: Bool) {
        guard width > 1, lineLimit >= 1 else { return (AttributedString(string), false) }
        let font = systemFont(fontSize)
        let ns = string as NSString
        let breaks = lineBreaks(string, font: font, width: width)
        if breaks.count <= lineLimit { return (AttributedString(string), false) }

        let starts = [0] + breaks
        var lines = (0..<(lineLimit - 1)).map { i in
            ns.substring(with: NSRange(location: starts[i], length: starts[i + 1] - starts[i]))
                .trimmingCharacters(in: .newlines)
        }
        // Break the remaining text at the reduced width so the last line leaves room for "MORE".
        let lastStart = starts[lineLimit - 1]
        let key = NSAttributedString.Key(kCTFontAttributeName as String)
        let attr = NSAttributedString(string: string, attributes: [key: font])
        let typesetter = CTTypesetterCreateWithAttributedString(attr)
        var n = CTTypesetterSuggestLineBreak(typesetter, lastStart, Double(max(10, width - reserve)))
        if n <= 0 { n = ns.length - lastStart }
        var last = ns.substring(with: NSRange(location: lastStart, length: n))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !last.hasSuffix("…") { last += "…" }
        lines.append(last)

        var body = AttributedString(lines.joined(separator: "\n") + " ")
        body.font = .system(size: fontSize)
        body.foregroundColor = palette.value
        var more = AttributedString("MORE")
        more.font = .system(size: fontSize, weight: .bold)
        more.foregroundColor = palette.more
        body += more
        return (body, true)
    }
}

/// An accessibility entry — an outlined badge (SDH / AD), styled like the hero metadata chips, above
/// its description.
private struct AccessibilityItem: View {
    let badge: String
    let description: String
    var palette: InfoPalette = .onDark

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            OutlinedBadge(text: badge, tint: palette.badge)
            Text(description)
                .font(.system(size: 23))
                .foregroundStyle(palette.accessory)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A focusable info column (Information / Languages / Accessibility). Plain text at rest, a card when
/// focused — but the button style is set ONCE and never swapped (tvOS drops focus the instant a focused
/// button's style changes, so a `.plain`↔`.card` swap makes the element un-focusable). Instead a single
/// style stays put and changes only its appearance on the element's own focus: nothing at rest, the
/// frosted card panel (the About card's look — 22 pt real padding, `.ultraThinMaterial`) plus the
/// native spring lift on focus. `spacing` sets the gap between items.
private struct InfoColumnCard<Content: View>: View {
    var spacing: CGFloat = 20
    @ViewBuilder var content: () -> Content

    var body: some View {
        Button { } label: {
            CardLabel(spacing: spacing, content: content)
        }
        .buttonStyle(CardFocusStyle())
    }

    /// Reads the button's focus from the environment so the frosted panel only shows while focused. The
    /// padding is constant regardless, so the text doesn't shift as focus moves between columns.
    private struct CardLabel<C: View>: View {
        let spacing: CGFloat
        @ViewBuilder var content: () -> C
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            VStack(alignment: .leading, spacing: spacing) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frostedInfoCard(padding: 22, bleedLeading: false, showsBackground: isFocused)
            // Same spring as CardFocusStyle's lift, so the frosted panel crossfades in step with the
            // scale rather than popping — the two together read as one native card focus.
            .animation(.spring(response: 0.34, dampingFraction: 0.72), value: isFocused)
        }
    }
}

// MARK: - Provider row (How to Watch) focus style

private struct ProviderRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(isFocused ? Theme.Color.cardFocused : Theme.Color.cardRest)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .stroke(isFocused ? Theme.Color.cardBorderFocused : .clear, lineWidth: 2)
                )
                .scaleEffect(configuration.isPressed ? 0.98 : (isFocused ? 1.02 : 1.0))
                .animation(.easeOut(duration: 0.18), value: isFocused)
        }
    }
}

// MARK: - Cast chip

/// Focus treatment for a cast chip — lifts and brightens the avatar (so the section is reachable
/// by the focus engine and matches Apple's focusable cast row).
private struct CastChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .brightness(isFocused ? 0.12 : 0)
                .scaleEffect(configuration.isPressed ? 0.97 : (isFocused ? 1.08 : 1.0))
                .animation(.easeOut(duration: 0.18), value: isFocused)
        }
    }
}

private struct CastChip: View {
    let name: String
    var role: String? = nil

    var body: some View {
        VStack(spacing: 12) {
            Circle()
                .fill(Theme.Color.cardRest)
                .frame(width: 140, height: 140)
                .overlay(
                    Text(initials)
                        .font(.title.weight(.bold))
                        .foregroundStyle(Theme.Color.primaryText.opacity(0.7))
                )
            VStack(spacing: 2) {
                Text(name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Theme.Color.primaryText.opacity(0.9))
                    .lineLimit(1)
                if let role {
                    Text(role)
                        .font(.caption)
                        .foregroundStyle(Theme.Color.secondaryText)
                        .lineLimit(1)
                }
            }
            .frame(width: 160)
            .multilineTextAlignment(.center)
        }
    }

    private var initials: String {
        let parts = name.split(separator: " ").compactMap { $0.first }.map(String.init)
        return parts.prefix(2).joined().uppercased()
    }
}

private extension View {
    /// Reports `zone == .content` while focused, when this view is part of the TOP content row. Crossing
    /// into/out of it (from/to the hero) drives the full-viewport scroll. Applied only to top-row items so
    /// navigating among lower shelves doesn't re-trigger the scroll; a no-op otherwise.
    @ViewBuilder
    func contentZone(_ active: Bool, _ binding: FocusState<MetaDetailView.Zone?>.Binding) -> some View {
        if active {
            focused(binding, equals: .content)
        } else {
            self
        }
    }

    /// Standard treatment for a detail row's horizontal `ScrollView`: don't clip the cards' focus lift,
    /// and lay the row out to the physical screen edges so its `leftInset` is measured from the same edge
    /// as the hero. (A nested ScrollView otherwise re-introduces the horizontal safe-area inset, leaving
    /// the rows pushed in relative to the hero column.)
    func detailRowScroll() -> some View {
        scrollClipDisabled()
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .horizontal)
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
