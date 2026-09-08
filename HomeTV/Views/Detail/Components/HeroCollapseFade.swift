import SwiftUI

/// Applies a State-A hero's collapse fade in isolation, for the same reason as `HeroCollapseParallax`:
/// it keeps the `scroll.heroOpacity` read out of `DetailHeroColumn`, so a scroll tick re-applies only an
/// `.opacity` rather than rebuilding the hero content.
struct HeroCollapseFade<Content: View>: View {
    let scroll: DetailScrollState
    @ViewBuilder var content: Content

    var body: some View {
        content
            .opacity(scroll.heroOpacity)   // Group A fades as it translates up (the scroll provides the translation)
    }
}
