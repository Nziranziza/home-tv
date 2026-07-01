import SwiftUI

struct WatchNowView: View {
    @State private var model = WatchNowViewModel()
    @State private var history = WatchHistory.shared
    @State private var trakt = TraktService.shared
    @State private var path: [MetaPreview] = WatchNowView.initialPath()
    @State private var streamRequest: StreamRequest?
    @State private var router = DeepLinkRouter.shared
    /// Shared hero carousel state, read by the pinned backdrop and the scrolling overlay alike.
    @State private var heroModel = HeroCarouselModel()
    /// Collapse clock: feeds the pinned backdrop's fade as the content sheet scrolls up over it.
    @State private var scrollState = WatchNowScrollState()
    @Namespace private var contentFocus
    @Environment(\.theme) private var theme

    /// Inactive while a detail is pushed or the stream picker modal is up, so the hero trailer isn't
    /// left decoding underneath either.
    private var isHeroActive: Bool { path.isEmpty && streamRequest == nil }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                theme.background.ignoresSafeArea()

                // Pinned hero backdrop, behind the scroll view so it stays fixed while the content sheet
                // scrolls up over it. Wrapped so only it (not this body, and so not the lazy rows) reads
                // the scroll clock: it fades out and drifts up a touch as the hero collapses.
                if !model.hasNoAddons {
                    PinnedHeroBackdrop(model: heroModel, scrollState: scrollState)
                }

                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // Scrolling hero content (logo/meta/buttons/dots) over the pinned backdrop. A
                        // focus section with its own scope defaulting to Play (Down from the tab bar
                        // lands here); sized below the viewport so the first row peeks at rest. Wrapped so
                        // its extra parallax read (it drifts up faster than the sheet) re-renders only the
                        // overlay on scroll, never WatchNowView.body or the lazy rows.
                        ParallaxHeroOverlay(scrollState: scrollState) {
                            HeroOverlay(
                                model: heroModel,
                                trakt: trakt,
                                defaultFocusNamespace: contentFocus,
                                onPlay: { meta in play(meta) },
                                onInfo: { meta in path.append(meta) }
                            )
                            // Sized to the viewport minus the sheet's peek strip, so the sheet's top sits
                            // on-screen at rest (the first row peeks) and the LazyVStack renders it.
                            .containerRelativeFrame(.vertical) { length, _ in
                                length - Theme.WatchNow.heroOverlayPeek
                            }
                        }
                        .focusSection()
                        .focusScope(contentFocus)

                        // Light content sheet that rises over the hero, carrying every row. Its top sits
                        // just below the hero's dots so the first row peeks at rest. Transparent at rest
                        // (rows on the dark hero); its light surface fades in only as you scroll.
                        WatchNowSheet(scrollState: scrollState) {
                            if !continueWatchingItems.isEmpty {
                                ContinueWatchingRow(items: continueWatchingItems) { item in
                                    path.append(item.preview)
                                }
                            }

                            ForEach(model.rowSpecs) { spec in
                                ContentRow(spec: spec) { meta in
                                    path.append(meta)
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .ignoresSafeArea()
                .contentMargins(.top, 0, for: .scrollContent)
                .onScrollGeometryChange(for: ScrollMetrics.self) {
                    ScrollMetrics(offset: $0.contentOffset.y, viewport: $0.containerSize.height)
                } action: { _, newValue in
                    scrollState.offset = newValue.offset
                    scrollState.viewport = newValue.viewport
                }

                if model.hasNoAddons {
                    emptyState
                }
            }
            .task(id: model.rowSpecs.first?.id) {
                await model.loadHero()
                heroModel.items = model.heroItems
            }
            .onChange(of: isHeroActive, initial: true) { _, active in
                heroModel.isActive = active
            }
            // Cold launch from a Top Shelf poster: the link may already be pending before the first
            // render, so onChange would miss it. Consume any waiting target on appear.
            .task { consumePendingDetail() }
            // Warm path: a poster tapped while the app is running flips pendingDetail.
            .onChange(of: router.pendingDetail) { _, _ in consumePendingDetail() }
            .metaDetailDestination()
            .streamPickerCover(request: $streamRequest)
        }
    }

    /// Continue Watching source: Trakt's playback progress when signed in (authoritative across
    /// devices), otherwise the local watch history recorded when you tap Play in HomeTV.
    private var continueWatchingItems: [WatchHistoryItem] {
        if trakt.isSignedIn {
            return trakt.continueWatchingItems.map { WatchHistoryItem(preview: $0) }
        }
        return history.items
    }

    /// Hero Play: record the title in history and open the stream picker directly (same flow as the
    /// detail screen's Play button), instead of only navigating to the detail page.
    private func play(_ meta: MetaPreview) {
        history.record(
            typeID: meta.type,
            metaID: meta.id,
            name: meta.name,
            poster: meta.poster,
            background: meta.background,
            logo: meta.logo
        )
        streamRequest = StreamRequest(
            type: meta.type,
            contentID: meta.id,
            title: meta.name,
            backgroundURL: meta.background,
            logoURL: meta.logo
        )
    }

    /// Presents the detail screen for a deep-linked title, if one is waiting. Replacing the whole
    /// navigation path makes this work from any state: cold launch (empty path), warm with nothing
    /// open, and — crucially — warm while another detail is already on the stack (the user opened one,
    /// pressed Home, then chose a Top Shelf poster). A path is a value collection, so swapping its
    /// contents always takes effect, unlike `navigationDestination(item:)` which ignores value→value.
    private func consumePendingDetail() {
        guard let pending = router.pendingDetail else { return }
        router.pendingDetail = nil
        path = [pending]
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            Text("No addons installed")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(theme.primaryText)
            Text("Add a Stremio addon from Settings to start browsing.")
                .font(.title3)
                .foregroundStyle(theme.secondaryText)
        }
    }

    private static func initialPath() -> [MetaPreview] {
        guard let raw = ProcessInfo.processInfo.environment["INITIAL_DETAIL"] else { return [] }
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return [] }
        return [.placeholder(type: parts[0], id: parts[1])]
    }

    /// Scroll geometry sampled each tick to drive the backdrop fade. Equatable so the action fires only
    /// when the values actually change.
    private struct ScrollMetrics: Equatable {
        let offset: CGFloat
        let viewport: CGFloat
    }
}

/// Wraps the pinned backdrop so it — and not `WatchNowView.body` — is what reads the scroll clock on
/// each tick. Keeping the clock reads out of the parent body means scrolling never re-evaluates the
/// (lazily loaded) catalog rows; only this small view re-renders to drift the backdrop and to pause the
/// trailer as the hero scrolls off. The backdrop stays at full brightness — the opaque content sheet
/// simply rises over it (Apple TV's Watch Now), so it's covered rather than dimmed.
private struct PinnedHeroBackdrop: View {
    let model: HeroCarouselModel
    let scrollState: WatchNowScrollState

    var body: some View {
        HeroBackdropLayer(model: model)
            .offset(y: scrollState.backdropParallax)
            // Pause the hero trailer once it scrolls off the top and resume it on return. Driven from
            // here — this wrapper already re-reads the scroll clock each tick — so the crossing never
            // touches WatchNowView.body or the lazily loaded catalog rows.
            .onChange(of: scrollState.isHeroVisible) { _, visible in
                model.setHeroVisible(visible)
            }
    }
}

/// Applies the hero overlay's extra scroll parallax in isolation: it reads the scroll clock each tick so
/// the wrapped overlay drifts up faster than the 1x content sheet, opening the dots→header gap as the
/// hero races off the top. Keeping the read here (not in `WatchNowView.body`) means scrolling re-renders
/// only this wrapper, never the lazily loaded catalog rows. The offset is visual only, so the overlay's
/// layout slot — and thus the sheet's position and the focus engine's scroll target — is unchanged.
private struct ParallaxHeroOverlay<Content: View>: View {
    let scrollState: WatchNowScrollState
    @ViewBuilder var content: Content

    var body: some View {
        content
            .offset(y: scrollState.heroParallax)
    }
}
