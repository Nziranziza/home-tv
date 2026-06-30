import SwiftUI

/// The collapse clock for the Watch Now hero, isolated into an `@Observable` so only the views that
/// read it (the pinned backdrop and the sheet's light surface) re-render on each scroll tick — the
/// content rows never read it, so scrolling doesn't re-evaluate the (lazily loaded) catalogs.
///
/// It drives two coordinated cross-fades, mirroring Apple TV's Watch Now:
/// - the pinned backdrop fades *out* as the hero scrolls off, and
/// - the light content sheet fades *in* as it rises — but is fully transparent at rest, so the peeking
///   first row sits on the dark hero with no light background until you actually scroll.
@MainActor
@Observable
final class WatchNowScrollState {
    /// Updated on each scroll tick from `onScrollGeometryChange`.
    var offset: CGFloat = 0
    var viewport: CGFloat = 0

    /// Pinned backdrop opacity: full at rest (the peeking first row sits on the dark hero), fading as
    /// the hero scrolls off so the page resolves to flat light colour in the deep rows.
    var backdropOpacity: Double {
        Double(1 - ramp(from: Theme.WatchNow.backdropFadeStartFraction,
                        to: Theme.WatchNow.backdropFadeEndFraction))
    }

    /// Light content-sheet opacity: 0 at rest — the sheet is fully transparent so the peeking first row
    /// shows the dark hero directly behind it (no light background at rest) — ramping to 1 as the sheet
    /// rises during scroll, so the opaque light surface fades in only while scrolling.
    var sheetSurfaceOpacity: Double {
        Double(ramp(from: Theme.WatchNow.sheetRevealStartFraction,
                    to: Theme.WatchNow.sheetRevealEndFraction))
    }

    /// Gentle upward drift of the pinned backdrop while the content scrolls over it at full rate, so the
    /// hero reads as pushed up a touch (parallax depth). Clamped to the viewport so it never exposes the
    /// backdrop's top edge.
    var backdropParallax: CGFloat {
        -min(max(offset, 0), viewport) * Theme.WatchNow.backdropParallaxFactor
    }

    /// Extra upward drift of the *scrolling* hero overlay (logo/meta/buttons/page dots) on top of its
    /// natural 1x scroll, so the hero pulls away faster than the content sheet beneath it. The dots lift
    /// off the rising sheet edge and a (backdrop-coloured) gap opens between them as you scroll — Apple
    /// TV's Watch Now parallax — while the gap stays tight at rest (zero drift at offset 0). Clamped to
    /// the viewport like `backdropParallax`, so the drift stays bounded (the overlay is fully off-screen
    /// by then anyway); the offset is visual only, so the layout slot and focus scroll-target are unchanged.
    var heroParallax: CGFloat {
        -min(max(offset, 0), viewport) * Theme.WatchNow.heroParallaxFactor
    }

    /// How far the light sheet's opaque surface extends above its content top (the first row header) at
    /// the current scroll position. Zero at rest (the surface starts right at the header, but is fully
    /// transparent there anyway) and grows as you scroll so a band of light fills the space the hero
    /// vacates above the header — matching Apple TV — capped so it never overshoots the whole hero.
    var sheetSurfaceTopOvershoot: CGFloat {
        min(max(offset, 0) * Theme.WatchNow.sheetSurfaceOvershootFactor,
            Theme.WatchNow.sheetSurfaceOvershootMax)
    }

    /// Linear 0→1 ramp over a viewport-fraction window of the scroll offset (resolution-independent).
    private func ramp(from startFraction: CGFloat, to endFraction: CGFloat) -> CGFloat {
        guard viewport > 0 else { return 0 }
        let start = viewport * startFraction
        let end = viewport * endFraction
        guard end > start else { return offset > start ? 1 : 0 }
        return min(max((offset - start) / (end - start), 0), 1)
    }
}
