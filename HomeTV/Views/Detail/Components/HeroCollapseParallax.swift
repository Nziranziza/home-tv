import SwiftUI

/// Applies a State-A hero's upward parallax drift in isolation — the one view that depends on
/// `scroll.offset`.
///
/// It exists so that `DetailHeroStage`'s content isn't what reads the scroll clock: a scroll tick then
/// re-renders only this tiny wrapper, re-applying a render-only `.offset`, instead of rebuilding the hero
/// column (which, on the title hero, would re-run the up-next episode scan). Mirrors Watch Now's
/// `ParallaxHeroOverlay`.
struct HeroCollapseParallax<Content: View>: View {
    let scroll: DetailScrollState
    @ViewBuilder var content: Content

    var body: some View {
        content
            .offset(y: -max(scroll.offset, 0) * DetailLayout.heroParallax)   // render-only parallax drift
    }
}
