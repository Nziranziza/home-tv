import SwiftUI

/// Layout constants for the detail screen, shared between the scroll-driven collapse math
/// (`DetailScrollState`) and the section views. Lifted out of `MetaDetailView` so the collapse math
/// can live next to the values it depends on, and so the section views read the same tokens.
enum DetailLayout {
    /// Hero region height as a fraction of the (top-safe-area-ignored) viewport. Near-full so the
    /// State-A column bottom-anchors with the action row at ≈ 88% down, and the collapse scrolls
    /// almost a full screen into the browse state.
    static let heroHeightFraction: CGFloat = 0.978
    /// Extra upward drift on the hero so it exits a bit faster than the content rises (× scroll speed).
    static let heroParallax: CGFloat = 0.3
    /// Top inset on the first content row so it rests at ≈ y224 (clear below the pinned logo) in State B.
    static let browseTopInset: CGFloat = 217
    /// Base upward pull on the content so the bare card peeks below the hero in State A.
    static let heroBottomPull: CGFloat = 110
    /// Vertical gap between stacked sections.
    static let interSectionSpacing: CGFloat = 56

    // About + Information block geometry.
    static let infoCardWidth: CGFloat = 565
    static let infoBlockInset: CGFloat = 80
    static let infoCardPadding: CGFloat = 24
    static let footerTopGap: CGFloat = 32
    static let footerPanelTopBleed: CGFloat = 30
}

/// The single clock for the hero↔browse collapse, isolated into an `@Observable` so only the chrome
/// views that actually read it (background, hero, centered logo, the section-header fade) re-render on
/// each scroll tick. The content sections (the 700-card episode strip, cast, related…) never read it,
/// so scrolling no longer re-evaluates them. Translation, opacity, blur, brightness, the logo fade —
/// all are functions of `p` and share this one clock.
@MainActor
@Observable
final class DetailScrollState {
    /// Updated on each scroll tick from `onScrollGeometryChange`.
    var offset: CGFloat = 0
    var viewport: CGFloat = 0

    /// The scroll offset at the State-B rest position (contentTop pinned to the top). `p` normalizes to
    /// THIS, not the hero height — the hero/content paddings shrink the scroll distance, so normalizing
    /// by the hero height alone leaves p < 1 at rest and the sharp background bleeds through the blur.
    var stateBScrollOffset: CGFloat {
        viewport * DetailLayout.heroHeightFraction
            - (DetailLayout.heroBottomPull + DetailLayout.browseTopInset)
            + DetailLayout.interSectionSpacing
    }

    /// Normalized collapse progress: 0 = State A (hero), 1 = State B (browse).
    var p: CGFloat {
        let denom = stateBScrollOffset
        guard denom > 0 else { return 0 }
        return min(max(offset / denom, 0), 1)
    }

    /// Element B — the small centered title logo — fades in around the midpoint of the collapse.
    var logoReveal: CGFloat { max(0, (p - 0.4) / 0.6) }

    /// Group A (the State-A hero column) fades as it translates up, with a floor just above 0 so the
    /// focus engine can still land on the hero buttons (tvOS won't focus an opacity-0 view).
    var heroOpacity: CGFloat { max(0.02, 1 - min(1, p * 1.3)) }
}
