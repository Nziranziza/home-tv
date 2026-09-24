import SwiftUI

/// The pinned-hero + rising-sheet page shared by Watch Now and the channel screen: a paging hero
/// backdrop behind a scroll view whose first slot is the hero overlay and whose sheet carries `rows`.
struct HeroSheetPage<Badge: View, Rows: View>: View {
    let heroModel: HeroCarouselModel
    var showsHero: Bool = true
    var onPlay: (MetaPreview) -> Void = { _ in }
    var onInfo: (MetaPreview) -> Void = { _ in }
    /// Drawn top-leading over the hero, scrolling with it (the channel screen's logo).
    @ViewBuilder var badge: Badge
    @ViewBuilder var rows: Rows

    /// Collapse clock: feeds the pinned backdrop's fade as the content sheet scrolls up over it.
    @State private var scrollState = WatchNowScrollState()
    @Namespace private var contentFocus
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            // Pinned hero backdrop, behind the scroll view so it stays fixed while the content sheet
            // scrolls up over it. Wrapped so only it (not this body, and so not the lazy rows) reads
            // the scroll clock: it fades out and drifts up a touch as the hero collapses.
            if showsHero {
                PinnedHeroBackdrop(model: heroModel, scrollState: scrollState)
            }

            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Scrolling hero content (logo/meta/buttons/dots) over the pinned backdrop. A
                    // focus section with its own scope defaulting to Play (Down from the tab bar
                    // lands here); sized below the viewport so the first row peeks at rest. Wrapped so
                    // its extra parallax read (it drifts up faster than the sheet) re-renders only the
                    // overlay on scroll, never the page body or the lazy rows.
                    ParallaxHeroOverlay(scrollState: scrollState) {
                        HeroOverlay(
                            model: heroModel,
                            defaultFocusNamespace: contentFocus,
                            onPlay: onPlay,
                            onInfo: onInfo
                        )
                        .overlay(alignment: .topLeading) { badge }
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
                        rows
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
        }
    }

    /// Scroll geometry sampled each tick to drive the backdrop fade. Equatable so the action fires only
    /// when the values actually change.
    private struct ScrollMetrics: Equatable {
        let offset: CGFloat
        let viewport: CGFloat
    }
}

extension HeroSheetPage where Badge == EmptyView {
    init(
        heroModel: HeroCarouselModel,
        showsHero: Bool = true,
        onPlay: @escaping (MetaPreview) -> Void = { _ in },
        onInfo: @escaping (MetaPreview) -> Void = { _ in },
        @ViewBuilder rows: () -> Rows
    ) {
        self.init(
            heroModel: heroModel,
            showsHero: showsHero,
            onPlay: onPlay,
            onInfo: onInfo,
            badge: { EmptyView() },
            rows: rows
        )
    }
}

/// Wraps the pinned backdrop so it — and not the page body — is what reads the scroll clock on
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
            // touches the page body or the lazily loaded catalog rows.
            .onChange(of: scrollState.isHeroVisible) { _, visible in
                model.setHeroVisible(visible)
            }
    }
}

/// Applies the hero overlay's extra scroll parallax in isolation: it reads the scroll clock each tick so
/// the wrapped overlay drifts up faster than the 1x content sheet, opening the dots→header gap as the
/// hero races off the top. Keeping the read here (not in the page body) means scrolling re-renders
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
