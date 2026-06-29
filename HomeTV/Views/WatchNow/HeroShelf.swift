import SwiftUI

struct HeroShelf: View {
    let items: [MetaPreview]
    /// False while a detail screen is pushed over Watch Now. A NavigationStack push doesn't disappear
    /// the root, so without this the covered hero keeps fetching + decoding a trailer (and could steal
    /// audio from the detail). When inactive the trailer is torn down; it reloads on return.
    var isActive: Bool = true
    var defaultFocusNamespace: Namespace.ID? = nil
    var onSelect: (MetaPreview) -> Void = { _ in }
    var onPlay: (MetaPreview) -> Void = { _ in }
    var onUpNext: (MetaPreview) -> Void = { _ in }
    var onInfo: (MetaPreview) -> Void = { _ in }

    @State private var index: Int = 0
    @State private var forward = true
    /// Inline trailer for the current featured title (Trailerio). Plays once, then pages on.
    @State private var trailerController = TrailerPlaybackController()
    @FocusState private var focusedControl: HeroControl?

    enum HeroControl: Hashable { case play, upNext, info, more }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                // Dark hero zone: backdrop + scrim clipped to the slot, so the hero ends at a clean
                // bottom edge. The light-gray page below shows through as a distinct zone — a clear
                // separation, not a blend. Clipping also contains the Ken Burns scale + page-slide.
                ZStack {
                    backdropLayer
                    HeroScrim()
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()

                // Focusable content + page dots.
                contentLayer
                if items.count > 1 {
                    HeroPageDots(count: items.count, current: index)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, Theme.Hero.pageDotsBottomPadding)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea(edges: [.horizontal, .top])
        // Item-reset: when the feed changes, jump back to the first title and warm its neighbors.
        // Keyed on items only — NOT isActive — so covering/uncovering the hero never resets the page.
        .task(id: items.map(\.id)) {
            index = 0
            prefetchNeighbors()
        }
        // Timer-driven auto-advance, gated on isActive so the carousel doesn't keep paging underneath
        // a pushed detail (a NavigationStack push doesn't disappear the root). Keyed on isActive as
        // well — kept separate from the item-reset task — so toggling active state pauses/resumes the
        // timer without disturbing the current index.
        .task(id: "\(items.map(\.id))|\(isActive)") {
            guard isActive else { return }
            await autoAdvance()
        }
        // Load + autoplay the current title's trailer (no loop — it pages on when the trailer ends).
        // Re-runs when the featured item changes or the hero is covered/uncovered (isActive), so a
        // covered hero tears its player down and a returning one reloads (candidates are cached).
        .task(id: "\(currentItem?.id ?? "none")|\(isActive)") {
            guard isActive, let meta = currentItem else { trailerController.teardown(); return }
            // Stop the previous item's trailer at once (before the await), so the old video doesn't
            // keep rendering over the new page while candidates are being fetched.
            trailerController.teardown()
            // Multi-item: play once then page on. Single item: loop (nothing to page to).
            trailerController.loops = items.count <= 1
            trailerController.onPlaybackEnded = { advance(by: 1) }
            let candidates = await TrailerSource.candidates(type: meta.type, id: meta.id)
            // Bail if the item changed (or the hero was covered) while fetching.
            guard !Task.isCancelled, !candidates.isEmpty else { return }
            trailerController.load(candidates)
            trailerController.autoplay()
        }
        .onChange(of: index) { prefetchNeighbors() }
        .onDisappear { trailerController.teardown() }
    }

    private var currentItem: MetaPreview? {
        items.indices.contains(index) ? items[index] : nil
    }

    // MARK: - Backdrop (current layer only; the next is prefetched into the image cache)

    private var backdropLayer: some View {
        ZStack {
            if let meta = currentItem {
                HeroBackdrop(url: meta.background.flatMap(URL.init(string:)))
                    .id(meta.id)
                    .transition(pageTransition)
            }
            // The inline trailer crossfades over the still once it's producing frames.
            TrailerVideoLayer(player: trailerController.player)
                .scaleEffect(Theme.Hero.trailerFillZoom)   // crop baked-in scope letterbox to fill the hero
                .opacity(trailerController.isReady ? 1 : 0)
                .animation(.easeInOut(duration: Theme.Hero.crossfadeDuration), value: trailerController.isReady)
                .allowsHitTesting(false)
        }
    }

    /// The text/art block crossfades per page (it's keyed by item id); the action row below does NOT
    /// carry an id, so it persists across pages and keeps the user's focus while they page with
    /// left/right. The whole block is bottom-anchored, so a taller info block grows upward and the
    /// buttons stay put.
    @ViewBuilder
    private var contentLayer: some View {
        VStack(alignment: .leading, spacing: Theme.Hero.contentSpacing) {
            ZStack(alignment: .bottomLeading) {
                if let meta = currentItem {
                    HeroInfo(meta: meta)
                        .id(meta.id)
                        .transition(pageTransition)
                }
            }
            .frame(maxWidth: .infinity, alignment: .bottomLeading)

            if let meta = currentItem {
                HeroActionRow(
                    focus: $focusedControl,
                    canPage: items.count > 1,
                    defaultFocusNamespace: defaultFocusNamespace,
                    onPlay: { onPlay(meta) },
                    onUpNext: { onUpNext(meta) },
                    onInfo: { onInfo(meta) },
                    onMore: { onSelect(meta) },
                    onPagePrevious: { advance(by: -1) },
                    onPageNext: { advance(by: 1) }
                )
            }
        }
        .padding(.horizontal, Theme.Hero.horizontalPadding)
        .padding(.bottom, Theme.Hero.bottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    /// Single place that moves the carousel, with wraparound + crossfade. Used by both manual
    /// edge-button paging (step ±1) and auto-advance (step +1).
    private func advance(by step: Int) {
        guard items.count > 1 else { return }
        forward = step > 0
        withAnimation(.easeInOut(duration: Theme.Hero.pageSlideDuration)) {
            index = (index + step + items.count) % items.count
        }
    }

    /// Horizontal page-slide that follows the paging direction: going forward, the new page enters
    /// from the trailing edge while the old exits leading; going back, the reverse. Used by BOTH the
    /// backdrop image and the text/logo content so the whole hero pages as one.
    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading),
            removal: .move(edge: forward ? .leading : .trailing)
        )
    }

    // MARK: - Auto-advance

    /// Rotates featured items on a timer, but pauses while the user is focused on a hero control
    /// (Apple TV behavior — content must not shift under an aimed button).
    private func autoAdvance() async {
        guard items.count > 1 else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Theme.Hero.autoAdvanceInterval))
            if Task.isCancelled { break }
            // Don't shift content under an aimed button, and don't yank a title mid-trailer — a playing
            // trailer pages on its own when it ends (onPlaybackEnded), so the timer stands down.
            if focusedControl != nil || trailerController.isReady { continue }
            advance(by: 1)
        }
    }

    /// Warm BOTH neighbors so a page-slide in either direction shows the real image immediately
    /// (it slides in already rendered) instead of a placeholder that pops in after.
    private func prefetchNeighbors() {
        guard items.count > 1 else { return }
        for offset in [1, -1] {
            let neighbor = (index + offset + items.count) % items.count
            guard let url = items[neighbor].background.flatMap(URL.init(string:)) else { continue }
            Task { await ImageLoader.shared.prefetch(url: url, targetSize: Theme.Hero.backdropTargetSize) }
        }
    }
}

// MARK: - Backdrop

private struct HeroBackdrop: View {
    let url: URL?

    @State private var drift = false

    var body: some View {
        RemoteImage(url: url, targetSize: Theme.Hero.backdropTargetSize, contentMode: .fill) {
            Color(white: 0.04)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(drift ? Theme.Hero.kenBurnsScale : Theme.Hero.kenBurnsBaseScale, anchor: .center)
        .offset(
            x: drift ? -Theme.Hero.kenBurnsOffsetX : Theme.Hero.kenBurnsOffsetX,
            y: drift ? -Theme.Hero.kenBurnsOffsetY : Theme.Hero.kenBurnsOffsetY
        )
        .animation(
            .easeInOut(duration: Theme.Hero.kenBurnsDuration).repeatForever(autoreverses: true),
            value: drift
        )
        .clipped()
        .onAppear { drift = true }
    }
}

// MARK: - Scrim

/// Three layered gradients: a top scrim so the tab bar reads over bright art, a left scrim behind
/// the text column, and a bottom scrim that fades into the light-gray page so the next row peeks.
private struct HeroScrim: View {
    var body: some View {
        ZStack {
            topGradient
            leftGradient
            bottomGradient
        }
    }

    private var topGradient: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.40), location: 0.0),
                .init(color: .black.opacity(0.0), location: 0.18)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var leftGradient: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.70), location: 0.0),
                .init(color: .black.opacity(0.15), location: 0.45),
                .init(color: .black.opacity(0.0), location: 0.65)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var bottomGradient: some View {
        // Moderate darkening for the hero's own text/buttons. Ends at the hero's clean bottom edge —
        // it does NOT fade to the page color, so the dark hero stays a distinct zone above the
        // light-gray content zone.
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.0), location: 0.4),
                .init(color: .black.opacity(0.35), location: 0.7),
                .init(color: .black.opacity(0.65), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Content

/// The per-page art/text: logo or title, metadata chips, tagline. Crossfades on page change.
private struct HeroInfo: View {
    let meta: MetaPreview

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Hero.contentSpacing) {
            HeroTitle(meta: meta)
            HeroMetaChips(meta: meta)
            if let tagline {
                HeroTagline(text: tagline)
            }
        }
    }

    private var tagline: String? {
        guard let desc = meta.description, !desc.isEmpty else { return nil }
        return desc
            .split(separator: ". ", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? desc
    }
}

private struct HeroTitle: View {
    let meta: MetaPreview

    var body: some View {
        if let url = meta.logo.flatMap(URL.init(string:)) {
            RemoteImage(
                url: url,
                targetSize: CGSize(width: Theme.Hero.logoMaxWidth, height: Theme.Hero.logoMaxHeight),
                contentMode: .fit
            ) {
                textTitle
            }
            .frame(
                maxWidth: Theme.Hero.logoMaxWidth,
                maxHeight: Theme.Hero.logoMaxHeight,
                alignment: .bottomLeading
            )
            .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
            .accessibilityLabel(meta.name)
        } else {
            textTitle
        }
    }

    private var textTitle: some View {
        Text(meta.name)
            .font(.system(size: 78, weight: .heavy))
            .foregroundStyle(.white)
            .lineLimit(2)
            .shadow(color: .black.opacity(0.7), radius: 12, y: 4)
            .frame(maxWidth: Theme.Hero.titleMaxWidth, alignment: .leading)
    }
}

private struct HeroMetaChips: View {
    let meta: MetaPreview
    /// Streaming-provider / network badge for the featured title (nil → no badge, like the detail
    /// hero). Resolved lazily per page via the shared, cached TMDB enrichment.
    @State private var providerBadgeURL: URL?

    var body: some View {
        MetaChipRow(parts: chips, trailingBadge: ratingText, leading: .provider(providerBadgeURL))
            .task(id: meta.id) {
                providerBadgeURL = await TMDBService.shared
                    .enrich(stremioType: meta.type, imdbID: meta.id)?.providerBadgeURL
            }
    }

    private var chips: [String] {
        var parts: [String] = [StremioType.displayLabel(for: meta.type)]
        if let year = meta.releaseInfo, !year.isEmpty { parts.append(year) }
        if let genres = meta.genres, !genres.isEmpty {
            parts.append(genres.prefix(2).joined(separator: ", "))
        }
        return parts
    }

    private var ratingText: String? {
        guard let rating = meta.imdbRating, !rating.isEmpty else { return nil }
        return "IMDb \(rating)"
    }
}

private struct HeroTagline: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 28))
            .foregroundStyle(.white.opacity(0.6))
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: Theme.Hero.taglineMaxWidth, alignment: .leading)
    }
}

private struct HeroActionRow: View {
    var focus: FocusState<HeroShelf.HeroControl?>.Binding
    let canPage: Bool
    var defaultFocusNamespace: Namespace.ID? = nil
    let onPlay: () -> Void
    let onUpNext: () -> Void
    let onInfo: () -> Void
    let onMore: () -> Void
    let onPagePrevious: () -> Void
    let onPageNext: () -> Void

    var body: some View {
        HStack(spacing: Theme.Hero.actionRowSpacing) {
            HeroPlayButton(title: "Play", icon: "play.fill", action: onPlay)
                .focused(focus, equals: .play)
                // Make Play the focus the engine lands on when entering Watch Now from the tab bar,
                // instead of the centered Continue Watching row below.
                .prefersHeroDefaultFocus(in: defaultFocusNamespace)
                // First button: a left press has no focus target, so it pages to the previous title.
                // Right/up/down aren't handled here, so they still move focus normally.
                .onMoveCommand { if canPage, $0 == .left { onPagePrevious() } }

            HeroCircleButton(icon: "plus", accessibilityLabel: "Add to Up Next", action: onUpNext)
                .focused(focus, equals: .upNext)
            HeroCircleButton(icon: "info", accessibilityLabel: "More Info", action: onInfo)
                .focused(focus, equals: .info)

            HeroCircleButton(icon: "chevron.right", accessibilityLabel: "More Like This", action: onMore)
                .focused(focus, equals: .more)
                // Last button: a right press has no focus target, so it pages to the next title.
                .onMoveCommand { if canPage, $0 == .right { onPageNext() } }
        }
        .padding(.top, Theme.Hero.actionRowTopPadding)
    }
}

private extension View {
    /// Applies `prefersDefaultFocus` only when a focus-scope namespace is supplied.
    @ViewBuilder
    func prefersHeroDefaultFocus(in namespace: Namespace.ID?) -> some View {
        if let namespace {
            prefersDefaultFocus(in: namespace)
        } else {
            self
        }
    }
}

// MARK: - Page dots

/// Apple TV-style hero pager: a centered run of dots with the active page as an elongated white
/// pill. When there are more pages than fit, the run is windowed around the current page and dots
/// shrink toward the edges to hint that more exist beyond the window.
private struct HeroPageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: Theme.Hero.pageDotsSpacing) {
            ForEach(visibleRange, id: \.self) { i in
                let isActive = i == current
                Capsule()
                    .fill(isActive ? Color.white : Color.white.opacity(0.45))
                    .frame(
                        width: isActive ? Theme.Hero.pageDotActiveWidth : Theme.Hero.pageDotSize * scale(for: i),
                        height: Theme.Hero.pageDotSize * (isActive ? 1.0 : scale(for: i))
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(
            Capsule(style: .continuous).fill(.black.opacity(0.28))
        )
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
        .animation(.easeInOut(duration: 0.35), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }

    /// Window of dots to draw, centered on the current page and clamped to the ends.
    private var visibleRange: Range<Int> {
        let maxVisible = Theme.Hero.pageDotsMaxVisible
        guard count > maxVisible else { return 0..<count }
        let half = maxVisible / 2
        var start = current - half
        var end = current + half + 1
        if start < 0 { end -= start; start = 0 }
        if end > count { start -= (end - count); end = count }
        return max(0, start)..<end
    }

    /// Dots shrink only at a window edge that has more pages hidden beyond it, so the indicator
    /// reads "there's more this way". When every page fits, all dots stay full size (Apple behavior).
    private func scale(for index: Int) -> CGFloat {
        let range = visibleRange
        if range.upperBound < count {
            switch range.upperBound - 1 - index {
            case 0: return 0.45
            case 1: return 0.7
            default: break
            }
        }
        if range.lowerBound > 0 {
            switch index - range.lowerBound {
            case 0: return 0.45
            case 1: return 0.7
            default: break
            }
        }
        return 1.0
    }
}

