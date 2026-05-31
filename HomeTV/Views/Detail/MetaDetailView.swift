import SwiftUI

struct MetaDetailView: View {
    let typeID: String
    let metaID: String
    let fallbackTitle: String

    @State private var registry = AddonRegistry.shared
    @State private var trakt = TraktService.shared
    @State private var meta: Meta?
    @State private var status: LoadStatus = .loading
    @State private var related: [MetaPreview] = []
    @State private var selectedSeason: Int?
    @FocusState private var focusedSeason: Int?
    @State private var relatedSelection: MetaPreview?
    @State private var streamRequest: StreamRequest? = MetaDetailView.initialStreamRequest()
    @State private var scrollOffset: CGFloat = 0
    @State private var didRevealUpNext = false

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
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 56) {
                        heroSection
                        if !seasons.isEmpty {
                            episodesSection
                        }
                        trailersSection
                        if !related.isEmpty {
                            relatedSection.id("related")
                        }
                        howToWatchSection
                        if let cast = meta?.cast, !cast.isEmpty {
                            castSection(cast: cast)
                        }
                        informationSection.id("information")
                    }
                }
                .ignoresSafeArea(edges: .top)
                .contentMargins(.top, 0, for: .scrollContent)
                .background(parallaxBackdrop)
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, newValue in
                    scrollOffset = newValue
                }
                .onChange(of: related.count) { _, newCount in
                    if newCount > 0,
                       let target = ProcessInfo.processInfo.environment["SCROLL_TO"] {
                        withAnimation { proxy.scrollTo(target, anchor: .top) }
                    }
                }
            }
        }
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

    // MARK: - Parallax backdrop

    private var backdropURL: URL? {
        (meta?.background ?? meta?.poster).flatMap(URL.init(string:))
    }

    /// Blurred, dimmed copy of the hero artwork filling the whole screen behind the page. It drifts
    /// slowly upward as the content scrolls (parallax), so the page reads as floating over the art
    /// rather than over flat black — matching Apple's detail screen.
    private var parallaxBackdrop: some View {
        GeometryReader { geo in
            RemoteImage(
                url: backdropURL,
                targetSize: Theme.Hero.backdropTargetSize,
                contentMode: .fill
            ) {
                Color(white: 0.05)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .scaleEffect(1.5)
            .blur(radius: 55)
            .offset(y: parallaxOffset)
            .overlay(
                LinearGradient(
                    colors: [.black.opacity(0.3), .black.opacity(0.55)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .clipped()
        }
        .ignoresSafeArea()
    }

    /// Background drifts up at a fraction of the scroll speed; clamped so the over-scaled image
    /// never reveals an edge no matter how far the page scrolls.
    private var parallaxOffset: CGFloat {
        -min(max(scrollOffset, 0) * 0.18, 220)
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop
            vignette
            heroContent
        }
        .frame(maxWidth: .infinity)
        .containerRelativeFrame(.vertical)
        .ignoresSafeArea(edges: [.horizontal, .top])
    }

    private var backdrop: some View {
        RemoteImage(
            url: backdropURL,
            targetSize: Theme.Hero.backdropTargetSize,
            contentMode: .fill
        ) {
            Color(white: 0.05)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var vignette: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.0), location: 0.0),
                    .init(color: .black.opacity(0.2), location: 0.45),
                    .init(color: Theme.Color.background.opacity(0.95), location: 0.95),
                    .init(color: Theme.Color.background, location: 1.0)
                ],
                startPoint: .top, endPoint: .bottom
            )
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.6), location: 0.0),
                    .init(color: .black.opacity(0.0), location: 0.65)
                ],
                startPoint: .leading, endPoint: .trailing
            )
        }
    }

    private var heroContent: some View {
        HStack(alignment: .bottom, spacing: 40) {
            VStack(alignment: .leading, spacing: 22) {
                titleView
                chipLine
                if let description = meta?.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(3)
                        .frame(maxWidth: 980, alignment: .leading)
                }
                metaLine
                actionButtons
                resumeBar
            }

            Spacer(minLength: 0)

            creditsColumn
        }
        .padding(.horizontal, 88)
        .padding(.bottom, 80)
    }

    @ViewBuilder
    private var titleView: some View {
        if let logo = meta?.logo, let url = URL(string: logo) {
            RemoteImage(url: url, targetSize: CGSize(width: 800, height: 220), contentMode: .fit) {
                titleTextFallback
            }
            .frame(maxWidth: 760, maxHeight: 200, alignment: .bottomLeading)
            .accessibilityLabel(meta?.name ?? fallbackTitle)
        } else {
            titleTextFallback
        }
    }

    private var titleTextFallback: some View {
        Text(meta?.name ?? fallbackTitle)
            .font(.system(size: 80, weight: .heavy))
            .foregroundStyle(Theme.Color.primaryText)
            .lineLimit(2)
    }

    // type · genre · genre  +  content-rating box (rating box is a PLACEHOLDER until addons provide it).
    // Reuses the shared `MetaChipRow` from the home hero.
    private var chipLine: some View {
        MetaChipRow(parts: typeAndGenreParts, trailingBadge: ratingPlaceholder, font: .title3)
    }

    // year · runtime · ★ imdb  +  quality badges (PLACEHOLDER until addons provide them)
    private var metaLine: some View {
        HStack(spacing: 14) {
            Text(factsLine)
                .font(.callout.weight(.medium))
                .foregroundStyle(Theme.Color.primaryText.opacity(0.8))
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

    // Reuses the shared hero buttons (HeroPlayButton / HeroCircleButton) from the home hero.
    private var actionButtons: some View {
        HStack(spacing: 18) {
            HeroPlayButton(title: playButtonTitle, icon: "play.fill") { startPlayback() }
            if trakt.isSignedIn {
                let inWatchlist = trakt.isInWatchlist(imdb: metaID)
                HeroCircleButton(
                    icon: inWatchlist ? "checkmark" : "plus",
                    accessibilityLabel: inWatchlist ? "Remove from Watchlist" : "Add to Watchlist"
                ) {
                    trakt.toggleWatchlist(type: typeID, imdb: metaID)
                }
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
                } else if typeID != "series" {
                    let watched = trakt.isWatched(type: typeID, imdb: metaID)
                    HeroCircleButton(
                        icon: watched ? "eye.slash" : "eye",
                        accessibilityLabel: watched ? "Mark as Unwatched" : "Mark as Watched"
                    ) {
                        trakt.toggleWatched(type: typeID, imdb: metaID)
                    }
                }
            } else {
                HeroCircleButton(icon: "plus", accessibilityLabel: "Add to Up Next") { }
            }
            HeroCircleButton(icon: "square.and.arrow.up", accessibilityLabel: "Share") { }
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
            VStack(alignment: .trailing, spacing: 10) {
                if !cast.isEmpty {
                    creditLine(label: "Starring", names: Array(cast.prefix(3)))
                }
                if !directors.isEmpty {
                    creditLine(label: "Director", names: directors)
                }
            }
            .frame(maxWidth: 380, alignment: .trailing)
        }
    }

    private func creditLine(label: String, names: [String]) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Color.primaryText.opacity(0.5))
            Text(names.joined(separator: ", "))
                .font(.callout.weight(.medium))
                .foregroundStyle(Theme.Color.primaryText.opacity(0.85))
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
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
                ScrollView(.horizontal, showsIndicators: false) {
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
                        }
                    }
                    .padding(.horizontal, 88)
                    .padding(.vertical, 24)
                }
                .scrollClipDisabled()
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
        ScrollView(.horizontal, showsIndicators: false) {
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
                    .id("season-\(season)")
                }
            }
            .padding(.horizontal, 88)
            .padding(.vertical, 8)
        }
        .scrollClipDisabled()
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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 28) {
                    trailerCard
                }
                .padding(.horizontal, 88)
                .padding(.vertical, 12)
            }
            .scrollClipDisabled()
        }
    }

    private var trailerCard: some View {
        Button { } label: {
            RemoteImage(
                url: (meta?.background ?? meta?.poster).flatMap(URL.init(string:)),
                targetSize: CGSize(width: 440, height: 248),
                contentMode: .fill
            ) {
                Color(white: 0.08)
            }
            .frame(width: 440, height: 248)
            // Dark scrim so the overlaid title/duration stays legible over the artwork.
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.85)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 140)
                .allowsHitTesting(false)
            }
            // Title + "▶ 3m" overlaid bottom-left, on the image (matches Apple — no separate bar).
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(meta?.name ?? fallbackTitle) Trailer")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: 7) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text("3m")   // PLACEHOLDER duration
                            .font(.system(size: 18, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.92))
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
            }
        }
        .buttonStyle(.card)
    }

    // MARK: - Related

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            DetailSectionHeader(title: "Related")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Row.posterCardSpacing) {
                    ForEach(related) { item in
                        ContentCard(meta: item) { relatedSelection = item }
                    }
                }
                .padding(.horizontal, 88)
                .padding(.vertical, 16)
            }
            .scrollClipDisabled()
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
            .buttonStyle(ProviderRowStyle())
            .padding(.horizontal, 88)
        }
    }

    // MARK: - Information (3-column block: Information / Languages / Accessibility)

    private var informationSection: some View {
        HStack(alignment: .top, spacing: 40) {
            informationColumn
            languagesColumn
            accessibilityColumn
        }
        .padding(.horizontal, 88)
        .padding(.top, 48)
        // Generous bottom region so the focus engine's auto-scroll (when a short column is focused)
        // never scrolls past the shelf to expose the blurred backdrop beneath it.
        .padding(.bottom, 600)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Full-bleed translucent "shelf" that runs to the left, right, and bottom screen edges,
        // separating the footer from the blurred content above.
        .background(
            Color.black.opacity(0.4)
                .ignoresSafeArea(edges: [.horizontal, .bottom])
        )
        .focusSection()
    }

    private var informationColumn: some View {
        InfoColumn(title: "Information") {
            if let year = meta?.releaseInfo, !year.isEmpty {
                InfoPair(label: "Released", value: year)
            }
            if let runtime = meta?.runtime, !runtime.isEmpty {
                InfoPair(label: "Run Time", value: runtime)
            }
            InfoPair(label: "Rated", value: ratingPlaceholder)   // PLACEHOLDER until addons provide it
            if let genres = meta?.genres, !genres.isEmpty {
                InfoPair(label: "Genre", value: genres.joined(separator: ", "))
            }
            // PLACEHOLDER — content advisories & regions aren't in Stremio's basic meta.
            InfoPair(label: "Content Advisories", value: "Violence, Language")
            InfoPair(label: "Regions of Origin", value: "United States")
        }
    }

    // PLACEHOLDER — language/audio/subtitle tracks come from the stream/addon, not basic meta.
    private var languagesColumn: some View {
        InfoColumn(title: "Languages") {
            InfoPair(label: "Original Audio", value: "English")
            InfoPair(
                label: "Audio",
                value: "English (Dolby Atmos, Dolby 5.1, AAC, AD), French, German, Italian, Spanish, Japanese",
                lineLimit: 4
            )
            InfoPair(
                label: "Subtitles",
                value: "English (CC, SDH), Arabic, Bulgarian, Chinese (Simplified & Traditional), Czech, Danish, Dutch, French, German, Spanish",
                lineLimit: 5
            )
        }
    }

    // PLACEHOLDER — accessibility flags come from the stream/addon, not basic meta.
    private var accessibilityColumn: some View {
        InfoColumn(title: "Accessibility", contentSpacing: 26) {
            AccessibilityItem(
                badge: "SDH",
                description: "Subtitles for the deaf and hard of hearing (SDH) refer to subtitles in the original language with the addition of relevant non-dialogue information."
            )
            AccessibilityItem(
                badge: "AD",
                description: "Audio descriptions (AD) refer to a narration track describing what is happening on screen, to provide context for those who are blind or have low vision."
            )
        }
    }

    // MARK: - Cast & Crew

    private func castSection(cast: [String]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            DetailSectionHeader(title: "Cast & Crew")
            ScrollView(.horizontal, showsIndicators: false) {
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
                .padding(.horizontal, 88)
                .padding(.vertical, 16)
            }
            .scrollClipDisabled()
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

    var body: some View {
        Text(title)
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(Theme.Color.primaryText.opacity(0.92))
            .padding(.horizontal, 88)
    }
}

// MARK: - Hero chip badges

/// PLACEHOLDER quality badges — real values (4K/HDR/Dolby/CC/AD) will come from addons.
private struct QualityBadges: View {
    private let badges = ["4K", "HDR", "CC", "AD"]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(badges, id: \.self) { badge in
                Text(badge)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(.white.opacity(0.18))
                    )
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
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

/// One focusable footer column: a header that stays put, plus a focusable content box that shows
/// the frosted highlight when focused (matching Apple). Each column is independently focusable, so
/// the focus engine can also scroll the page down to this footer.
/// Propagates a footer column's focus state down to its text so the labels/values can darken on the
/// light frosted panel (`\.isFocused` only reaches the button style, not the label's descendants).
private struct InfoColumnFocusedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var infoColumnFocused: Bool {
        get { self[InfoColumnFocusedKey.self] }
        set { self[InfoColumnFocusedKey.self] = newValue }
    }
}

private struct InfoColumn<Content: View>: View {
    let title: String
    var contentSpacing: CGFloat = 22
    @ViewBuilder var content: () -> Content

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            InfoColumnHeader(title: title)
            Button { } label: {
                VStack(alignment: .leading, spacing: contentSpacing) {
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .environment(\.infoColumnFocused, focused)
            }
            .buttonStyle(InfoColumnStyle())
            .focused($focused)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Frosted rounded highlight shown when a footer column is focused.
private struct InfoColumnStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.85))
                        .opacity(isFocused ? 1 : 0)
                )
                .scaleEffect(configuration.isPressed ? 0.99 : (isFocused ? 1.02 : 1.0))
                .shadow(color: .black.opacity(isFocused ? 0.35 : 0), radius: 20, y: 12)
                .animation(.easeOut(duration: 0.18), value: isFocused)
        }
    }
}

private struct InfoColumnHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 32, weight: .bold))
            .foregroundStyle(Theme.Color.primaryText)
            .padding(.bottom, 4)
    }
}

/// A label-over-value pair, e.g. "Released" / "2023". Text darkens when its column is focused so it
/// stays legible on the light frosted panel.
private struct InfoPair: View {
    let label: String
    let value: String
    var lineLimit: Int? = nil
    @Environment(\.infoColumnFocused) private var isFocused

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.callout)
                .foregroundStyle(isFocused ? .black.opacity(0.5) : Theme.Color.tertiaryText)
            Text(value)
                .font(.callout)
                .foregroundStyle(isFocused ? .black.opacity(0.9) : Theme.Color.primaryText.opacity(0.9))
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// An accessibility entry — an outlined badge (SDH / AD) above its description. Adapts to dark text
/// on the light frosted panel when its column is focused.
private struct AccessibilityItem: View {
    let badge: String
    let description: String
    @Environment(\.infoColumnFocused) private var isFocused

    private var tint: Color { isFocused ? .black.opacity(0.85) : .white.opacity(0.9) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(badge)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(tint.opacity(0.7), lineWidth: 1.2)
                )
                .foregroundStyle(tint)
            Text(description)
                .font(.callout)
                .foregroundStyle(isFocused ? .black.opacity(0.85) : Theme.Color.primaryText.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
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
