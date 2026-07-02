import SwiftUI

enum Theme {
    /// Fixed colors for the **immersive Detail surface** (the hero/browse screen, stream picker, cast
    /// and provider chips). That screen renders over full-bleed backdrop artwork and stays dark in
    /// every appearance, so these are deliberately constant and do NOT follow the active theme. Themed
    /// chrome (Watch Now, Search, Library, Settings) reads `@Environment(\.theme)` instead — see
    /// `ThemePalette`.
    enum Color {
        static let background = SwiftUI.Color.black

        static let cardRest = SwiftUI.Color.white.opacity(0.08)

        static let primaryText = SwiftUI.Color.white
        static let secondaryText = SwiftUI.Color.white.opacity(0.65)
        static let tertiaryText = SwiftUI.Color.white.opacity(0.40)

        static let destructive = SwiftUI.Color(red: 0.95, green: 0.32, blue: 0.32)
    }

    enum Radius {
        static let card: CGFloat = 18
        static let pill: CGFloat = 28
        static let tile: CGFloat = 14
        static let badge: CGFloat = 7
    }

    enum Spacing {
        static let rowVertical: CGFloat = 28
        static let rowHorizontal: CGFloat = 36
        static let stack: CGFloat = 16
        static let section: CGFloat = 40
    }

    /// One side margin for the list/grid pages — Search, Library, and Settings — so their content all
    /// lines up at the same left edge. Change it here to move every one of them together.
    ///
    /// Watch Now is intentionally NOT driven by this: its hero column uses `Hero.horizontalPadding` (80)
    /// and its catalog rows use `Row.contentInset` (88).
    enum Layout {
        static let horizontalMargin: CGFloat = 80
    }

    enum Hero {
        static let height: CGFloat = 980

        /// Target decode size for the full-bleed backdrop (tvOS renders at 1920×1080 points).
        static let backdropTargetSize = CGSize(width: 1920, height: 1080)

        /// Zoom applied to an inline hero trailer so a scope (≈2.39:1) clip — delivered letterboxed
        /// inside a 16:9 file — fills the 16:9 hero instead of showing its baked-in black bars. The
        /// bars are part of the pixels, so the only way to hide them is to scale up and crop the sides
        /// (fine for an ambient backdrop; the full-screen Trailers-row player stays un-zoomed). 1.0 = off.
        static let trailerFillZoom: CGFloat = 1.35

        static let autoAdvanceInterval: Double = 7
        static let crossfadeDuration: Double = 0.9
        /// Motion for the horizontal page-slide when the featured item changes. A decelerating,
        /// barely-underdamped spring — dampingFraction 0.9 is the same damping as the detail-hero collapse
        /// spring, so it glides to rest with at most an imperceptible overshoot rather than the symmetric
        /// easeInOut that reads as mechanical.
        static let pageSlideSpring: Animation = .spring(response: 0.5, dampingFraction: 0.9)

        static let kenBurnsDuration: Double = 22
        // Both scale ends stay zoomed enough that the pan offset never exposes an edge of the image
        // (base must comfortably cover kenBurnsOffsetX/Y). The animation pans between the two.
        static let kenBurnsBaseScale: CGFloat = 1.08
        static let kenBurnsScale: CGFloat = 1.16
        static let kenBurnsOffsetX: CGFloat = 22
        static let kenBurnsOffsetY: CGFloat = 16

        // Left gutter for the hero column, matched to Apple TV's Watch Now (measured at 80 pt on the
        // 1920-pt canvas). The catalog rows keep their own slightly-wider `Row.contentInset` (88).
        static let horizontalPadding: CGFloat = 80
        // Bottom-anchored hero content sits in the lower third (≈ buttons at 71% of the screen, on a
        // 1080-pt viewport), just above the page dots and the content sheet that peeks below — matching
        // Apple TV's Watch Now hero. Measured from the overlay's bottom edge, which sits at the top of
        // the peeking sheet (see `WatchNow.heroOverlayPeek`), not the screen bottom.
        static let bottomPadding: CGFloat = 80
        static let contentSpacing: CGFloat = 22
        static let actionRowSpacing: CGFloat = 22
        static let actionRowTopPadding: CGFloat = 6
        static let metaChipsSpacing: CGFloat = 14
        // Page dots sit just above the sheet's top edge (the overlay's bottom). Together with the
        // sheet's small top padding this keeps the dots close to the Continue Watching header — the
        // tight gap Apple TV uses, not a wide band.
        static let pageDotsBottomPadding: CGFloat = 4
        static let pageDotsSpacing: CGFloat = 8
        static let pageDotSize: CGFloat = 8
        static let pageDotActiveWidth: CGFloat = 22
        static let pageDotsMaxVisible: Int = 9
        // Inset of the dots run within its rounded pill platter.
        static let pageDotsPillHorizontalPadding: CGFloat = 16
        static let pageDotsPillVerticalPadding: CGFloat = 9

        static let buttonHeight: CGFloat = 66
        static let primaryButtonHorizontalPadding: CGFloat = 44

        static let sourceBadgeSize: CGFloat = 30

        static let titleMaxWidth: CGFloat = 1100
        // Logo art fit box, sized to Apple TV's Watch Now: a hero logo there measures ≈150 pt tall and
        // ≈420 pt wide (e.g. Echo Valley 419×152). The box caps height first so tall/2-line logos land at
        // Apple's scale, with the width cap only reining in unusually wide wordmarks.
        static let logoMaxWidth: CGFloat = 500
        static let logoMaxHeight: CGFloat = 150

        // MARK: Shared hero text
        // The Watch Now hero and the Detail hero read identically, so both draw their text from these one
        // values — change a value here to move BOTH. `HeroDescription` and `MetaChipRow`'s default font
        // consume them directly; the title font is applied by each hero, which keeps its own shadow/width
        // treatment around the shared size.
        static let titleFallbackFont: Font = .system(size: 52, weight: .heavy)
        static let chipFont: Font = .system(size: 26, weight: .medium)
        static let descriptionFont: Font = .system(size: 27)
        static let descriptionOpacity: Double = 0.68
        static let descriptionLineSpacing: CGFloat = 6
        static let descriptionLineLimit: Int = 4
        static let descriptionMaxWidth: CGFloat = 780
    }

    enum WatchNow {
        static let interRowSpacing: CGFloat = 48
        static let bottomPadding: CGFloat = 100

        /// How tall a strip of the content sheet peeks below the hero at rest (≈ first row's header +
        /// card tops), like Apple TV. The hero overlay is sized to the viewport *minus* this, so the
        /// sheet's top sits on-screen and the (lazy) sheet actually renders — pulling a full-height
        /// overlay up with a negative inset leaves the sheet below the fold, so `LazyVStack` never
        /// materializes it.
        static let heroOverlayPeek: CGFloat = 200

        /// Scroll distance (as a fraction of the viewport) past which the hero trailer pauses: once this
        /// much has scrolled up the hero is reduced to a thin sliver above the content sheet — too small
        /// to watch — so playback (and its audio) stops rather than running for a strip you can't see.
        /// Set below the point where that sliver appears, so the trailer stops before the hero shrinks to
        /// it, not right as it does.
        static let heroTrailerPauseFraction: CGFloat = 0.6

        /// Scroll window over which the (opaque) light content sheet reveals. It starts at 0 and is
        /// transparent *at rest* (fraction 0 → opacity 0), so the peeking first row shows the dark hero
        /// directly behind it — there is no light background at rest. The window is deliberately short:
        /// the sheet snaps to fully opaque within the first sliver of scroll, so it is never a lingering
        /// translucent wash over the backdrop (Apple TV's sheet is opaque — the artwork only shows in the
        /// dark band *above* its rising top edge, never through the sheet body).
        static let sheetRevealStartFraction: CGFloat = 0.0
        static let sheetRevealEndFraction: CGFloat = 0.08

        /// Gentle upward drift of the pinned backdrop per point of scroll, so the hero reads as pushed up
        /// a touch while the content rises over it at full rate (parallax depth, like Apple TV). 0 = off.
        static let backdropParallaxFactor: CGFloat = 0.12

        /// Extra upward drift of the scrolling hero overlay (logo/meta/buttons/page dots) per point of
        /// scroll, on top of its natural 1x scroll. The hero pulls away faster than the 1x content sheet,
        /// so the page dots lift off the rising sheet edge and a gap opens between them while scrolling —
        /// matching Apple TV, where the dots→header gap grows as the hero races off the top. 0 = rigid.
        static let heroParallaxFactor: CGFloat = 0.22

        /// How far the light sheet's surface extends *above* its content top (the first row header) per
        /// point of scroll. Lets the opaque surface grow upward into the space the hero vacates, so a
        /// band of light appears above the header as you scroll — without widening the tight dots→header
        /// gap at rest (zero overshoot at offset 0). Capped in the scroll state so it never runs away.
        static let sheetSurfaceOvershootFactor: CGFloat = 0.12
        static let sheetSurfaceOvershootMax: CGFloat = 80

        /// Top padding inside the sheet, between its (flat, full-width) top edge and the first row's
        /// header. Small, so the Continue Watching header sits just below the page dots (which hover
        /// just above the edge) — the tight dots→header gap Apple TV uses.
        static let sheetTopPadding: CGFloat = 2

        /// Fixed medium grey for the catalog row headers (Continue Watching, catalog names). Constant —
        /// not themed — so it reads identically on the dark hero at rest and the light sheet when
        /// scrolled, matching Apple TV. A `.black.opacity()` header would disappear against the hero.
        static let rowHeaderColor = SwiftUI.Color(red: 0.45, green: 0.45, blue: 0.47)
    }

    /// Search screen — the keyboard, query header and "Press ⏯…" hint are the native tvOS
    /// `.searchable` UI, so only the Browse grid's geometry lives here. Card size and gutter were
    /// measured from the reference frame (`ignore/search.png`, 1920×1080); the side margin is the
    /// shared `Layout.horizontalMargin`.
    enum Search {
        static let posterSize = CGSize(width: 260, height: 391)
        static let posterGutter: CGFloat = 40
        static let posterRowGap: CGFloat = 58
        static let posterColumns: Int = 6
    }

    /// Detail screen (Apple TV+ style hero ↔ browse). One left alignment guide for ALL left-aligned
    /// content in both states, so the hero column and the content rows share a single guide. Measured
    /// from the reference video frames (hero metadata, headers, cards, and posters all align here).
    enum Detail {
        static let leftInset: CGFloat = 86

        /// Uniform height of a content row's header slot (the band that holds a section label or the
        /// season selector, directly above the row's cards). Fixing it — and bottom-anchoring taller
        /// content so it overflows upward — keeps the hero peek below the row identical regardless of
        /// what the header contains, so a one-line "Episodes" label and a row of season tabs reserve
        /// exactly the same space. Sized to a 30 pt semibold section label.
        static let rowHeaderHeight: CGFloat = 36
    }

    /// Horizontal rows of cards (catalogs, Continue Watching). `contentInset` is the catalog gutter for
    /// Watch Now; the hero column uses its own (slightly narrower) `Hero.horizontalPadding` of 80.
    enum Row {
        static let contentInset: CGFloat = 88

        static let posterHeight: CGFloat = 422
        static let posterVerticalPadding: CGFloat = 16
        static let posterCardSpacing: CGFloat = 36

        static let landscapeHeight: CGFloat = 360
        static let landscapeVerticalPadding: CGFloat = 32
        static let landscapeCardSpacing: CGFloat = 28

        // Header→cards spacing, shared by every row (matches Continue Watching). A touch wider than the
        // dots→header gap above it, mirroring Apple TV.
        static let headerSpacing: CGFloat = 16
        static let continueWatchingVerticalPadding: CGFloat = 16
        // Apple's Continue Watching uses a slightly wider gap (~10.5% of card width) than other
        // landscape rows; dedicated so it doesn't widen those.
        static let continueWatchingCardSpacing: CGFloat = 34
    }

    /// Card geometry + the shared focus treatment (see `focusableCard`).
    enum Card {
        static let posterSize = CGSize(width: 260, height: 390)
        static let landscapeSize = CGSize(width: 460, height: 258)
        static let squareSide: CGFloat = 300
        static let continueWatchingSize = CGSize(width: 320, height: 230)

        static let captionSpacing: CGFloat = 12

        static let focusScale: CGFloat = 1.04
        static let focusShadowRadius: CGFloat = 22
        static let focusShadowYOffset: CGFloat = 14
        static let focusShadowOpacity: Double = 0.32
        static let focusAnimationDuration: Double = 0.22
    }
}

/// The lift + shadow every focusable card shares. One source of truth so cards animate identically.
struct FocusableCardModifier: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isFocused ? Theme.Card.focusScale : 1.0)
            .shadow(
                color: .black.opacity(isFocused ? Theme.Card.focusShadowOpacity : 0.0),
                radius: isFocused ? Theme.Card.focusShadowRadius : 0,
                y: isFocused ? Theme.Card.focusShadowYOffset : 0
            )
            .animation(.easeOut(duration: Theme.Card.focusAnimationDuration), value: isFocused)
    }
}

extension View {
    func focusableCard(isFocused: Bool) -> some View {
        modifier(FocusableCardModifier(isFocused: isFocused))
    }

    /// Lays a page's scrolling content edge-to-edge horizontally so the ONLY horizontal inset is the
    /// explicit `Layout.horizontalMargin` the content applies itself. It strips the two implicit
    /// insets tvOS otherwise adds — the overscan safe area and the scroll view's default content
    /// margins — which is what made Library and Settings sit further in than Search (Search escapes
    /// them via `.searchable`). Apply to the page `ScrollView`; keep the vertical safe area so content
    /// still clears the tab bar.
    func pageHorizontalInsets() -> some View {
        self
            .ignoresSafeArea(.container, edges: .horizontal)
            .contentMargins(.horizontal, 0, for: .scrollContent)
    }
}

/// Card focus style with a gentle lift and a SOFT, subtle shadow — much lighter than the system
/// `.buttonStyle(.card)` shadow, which is too heavy on light backgrounds. No focus ring. Tune the
/// shadow values below to taste.
struct CardFocusStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.98 : (isFocused ? 1.04 : 1.0))
                .shadow(
                    color: .black.opacity(isFocused ? 0.18 : 0),
                    radius: isFocused ? 14 : 0,
                    y: isFocused ? 8 : 0
                )
                // Spring (not ease) so the lift settles with the same decelerating bounce-free motion
                // tvOS's own `.card` focus uses — this is what makes a focus-driven style read as native
                // rather than "fake".
                .animation(.spring(response: 0.34, dampingFraction: 0.72), value: isFocused)
        }
    }
}

/// Circular icon button (e.g. the close "✕"). Owns its focus treatment so the
/// system's default rounded-rect highlight doesn't fight the circular shape —
/// on focus it fills solid and inverts the glyph, like tvOS system controls.
struct CircularIconButtonStyle: ButtonStyle {
    var diameter: CGFloat = 70

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, diameter: diameter)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let diameter: CGFloat
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .font(.title3.weight(.bold))
                .foregroundStyle(isFocused ? .black : Theme.Color.primaryText)
                .frame(width: diameter, height: diameter)
                .background(
                    Circle().fill(isFocused ? Theme.Color.primaryText : Theme.Color.cardRest)
                )
                .scaleEffect(configuration.isPressed ? 0.94 : (isFocused ? 1.12 : 1.0))
                .shadow(color: .black.opacity(isFocused ? 0.35 : 0),
                        radius: isFocused ? 16 : 0, y: isFocused ? 8 : 0)
                .animation(.easeOut(duration: 0.18), value: isFocused)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

struct SettingsCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SettingsCardBody(configuration: configuration)
    }

    private struct SettingsCardBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused
        @Environment(\.theme) private var theme

        var body: some View {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.rowHorizontal)
                .padding(.vertical, Theme.Spacing.rowVertical)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(isFocused ? theme.cardFocused : theme.cardRest)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .stroke(isFocused ? theme.cardBorderFocused : .clear, lineWidth: 2)
                )
                // Soft lift so the focused row reads above the page in light, where a fill swap alone
                // is too subtle (matches the gentle-shadow language of CardFocusStyle).
                .shadow(color: .black.opacity(isFocused ? 0.12 : 0),
                        radius: isFocused ? 16 : 0, y: isFocused ? 8 : 0)
                .scaleEffect(configuration.isPressed ? 0.97 : (isFocused ? 1.015 : 1.0))
                .animation(.easeInOut(duration: 0.18), value: isFocused)
                .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(theme.primaryText)
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }
}

struct ScreenTitle: View {
    let title: String
    var subtitle: String? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(theme.primaryText)
            if let subtitle {
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 12)
    }
}

struct RowHeader: View {
    let title: String
    var subtitle: String? = nil
    /// Overrides the themed header colour. Watch Now passes a fixed medium grey so the header reads the
    /// same whether it sits on the dark hero (at rest) or the light sheet (scrolled) — a themed
    /// black-opacity colour would vanish against the hero.
    var color: SwiftUI.Color? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(color ?? theme.rowHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(theme.tertiaryText)
            }
        }
        .padding(.horizontal, Theme.Row.contentInset)
    }
}
