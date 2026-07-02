import SwiftUI

/// Which region currently holds focus on a detail-style screen. Crossing the hero↔content boundary
/// drives the full-viewport collapse scroll. Shared by the title detail (`MetaDetailView`) and the
/// single-episode detail (`EpisodeDetailView`) so both use the same scaffold wiring.
enum DetailZone: Hashable { case hero, content }

/// The shared shell for a detail-style screen: a fixed page backdrop, a vertical `ScrollView` whose
/// geometry drives the collapse clock, and the hero↔content full-viewport scroll keyed on the focus
/// `zone`. Both the title detail and the episode detail render their own backdrop and content column
/// into it, so the (finely tuned) collapse/scroll/zone machinery lives in exactly one place.
///
/// The content builder receives the `ScrollViewProxy` so a screen can drive extra programmatic scrolls
/// (e.g. a deep-link "scroll to section") without the scaffold needing to know about them.
struct DetailScaffold<Background: View, Content: View>: View {
    let scroll: DetailScrollState
    var zone: FocusState<DetailZone?>.Binding
    @ViewBuilder var background: () -> Background
    @ViewBuilder var content: (ScrollViewProxy) -> Content

    /// Scroll offset + viewport height, read on each scroll tick; drives the collapse clock.
    private struct ScrollMetrics: Equatable {
        var offset: CGFloat
        var viewport: CGFloat
    }

    var body: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()

            // Fixed backdrop; everything scrolls above it.
            background()

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    content(proxy)
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
                    scroll.offset = newValue.offset
                    scroll.viewport = newValue.viewport
                }
                // Crossing the hero↔content boundary scrolls the full viewport (hero off / back).
                .onChange(of: zone.wrappedValue) { _, newZone in
                    switch newZone {
                    case .content:
                        withAnimation(heroScroll) { proxy.scrollTo("contentTop", anchor: .top) }
                    case .hero:
                        withAnimation(heroScroll) { proxy.scrollTo("heroTop", anchor: .top) }
                    case .none:
                        break
                    }
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)   // full-screen detail (no tab bar over the content)
    }

    /// The single clock for the whole hero↔browse interaction. Translation, opacity, blur, brightness,
    /// saturation, the logo fade, and the trailer-card focus-lift are ALL functions of `p` and animate
    /// on this one spring — decelerating, no bounce, no overshoot. (Matches the reference exactly; the
    /// usual reason a copy looks off is desynced / differently-eased sub-animations.)
    private var heroScroll: Animation { .spring(response: 0.55, dampingFraction: 0.9) }
}
