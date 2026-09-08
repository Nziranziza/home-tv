import SwiftUI

/// Frames a State-A hero and applies its collapse parallax drift: the hero fills (almost) the viewport,
/// bleeds past the horizontal and top safe areas, carries the `heroTop` scroll id, and drifts upward as
/// the content rises. Shared by the title detail hero and the episode hero, which stage identically.
///
/// The scroll clock is read by the private `HeroCollapseParallax` child, NOT by this body — so a scroll
/// tick re-renders only that tiny wrapper and never rebuilds the hero content (which, on the title hero,
/// would re-run the up-next episode scan). The wrapped content is built once by the parent and only has a
/// render-only `.offset` re-applied. Mirrors Watch Now's `ParallaxHeroOverlay`.
struct DetailHeroStage<Content: View>: View {
    let scroll: DetailScrollState
    @ViewBuilder var content: Content

    var body: some View {
        HeroCollapseParallax(scroll: scroll) {
            content
                .containerRelativeFrame(.vertical) { length, _ in length * DetailLayout.heroHeightFraction }
                .ignoresSafeArea(edges: [.horizontal, .top])
                .id("heroTop")
        }
    }
}

/// Applies the hero's upward parallax drift in isolation — the one view that depends on `scroll.offset`.
private struct HeroCollapseParallax<Content: View>: View {
    let scroll: DetailScrollState
    @ViewBuilder var content: Content

    var body: some View {
        content
            .offset(y: -max(scroll.offset, 0) * DetailLayout.heroParallax)   // render-only parallax drift
    }
}
