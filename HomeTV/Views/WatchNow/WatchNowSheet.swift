import SwiftUI

/// The light "content sheet" that carries every catalog row over the dark hero. Its light surface is
/// **scroll-gated**: at rest it is fully transparent, so the peeking first row sits directly on the
/// dark hero (no light background until you scroll). As you scroll, the surface — a flat *opaque* page
/// colour — snaps in and rises, fully occluding the hero behind it (never translucent: the backdrop
/// only ever shows in the dark band *above* the sheet's hard top edge, exactly like Apple TV's Watch
/// Now). Once scrolled past the hero the page is flat page colour throughout.
///
/// The surface reads the scroll clock from an isolated child (`WatchNowSheetSurface`) so this view's
/// body never touches the clock — scrolling re-renders only the surface, never the (lazy) rows.
struct WatchNowSheet<Content: View>: View {
    let scrollState: WatchNowScrollState
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.WatchNow.interRowSpacing) {
            content
        }
        .padding(.top, Theme.WatchNow.sheetTopPadding)
        .padding(.bottom, Theme.WatchNow.bottomPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WatchNowSheetSurface(scrollState: scrollState))
    }
}

/// The sheet's light surface, split out so it is the only thing that re-renders as you scroll: it reads
/// `sheetSurfaceOpacity` from the scroll clock and reveals a flat *opaque* page-colour surface — from
/// invisible at rest to fully present once scrolling. Opaque by design: it fully occludes the hero, so
/// the backdrop is never seen *through* the sheet (only above its hard top edge).
private struct WatchNowSheetSurface: View {
    let scrollState: WatchNowScrollState
    @Environment(\.theme) private var theme

    var body: some View {
        theme.background
            // Flat, full-width top edge with a crisp horizontal boundary — no rounded corners and no
            // feather: Apple TV's Watch Now sheet meets the dark hero on a clean hard line (a soft fade
            // here just reads as a glowing translucent band over the backdrop). Extend below the last
            // row to the screen bottom so there's no seam against the page base.
            .ignoresSafeArea(edges: .bottom)
            // Grow the surface *upward* past its content top as you scroll, filling the band the hero
            // vacates above the first row's header (the light region over the dark hero in Apple TV's
            // demo) — without widening the tight dots→header gap at rest, where the overshoot is zero.
            .padding(.top, -scrollState.sheetSurfaceTopOvershoot)
            // Hidden at rest → the peeking first row sits on the dark hero; snaps to fully opaque almost
            // immediately as you scroll (short reveal window), never a lingering translucent wash.
            .opacity(scrollState.sheetSurfaceOpacity)
    }
}
