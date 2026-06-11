import SwiftUI

/// A complete set of semantic colors for one app appearance. The app renders a single palette at a
/// time, injected through the environment (`\.theme`), so every view resolves its colors from the
/// active appearance rather than hard-coding light/dark values. Adding a new appearance is a value
/// swap — define another `ThemePalette` and inject it — with no changes at the call sites.
///
/// Scope: these are *chrome* colors — the page background, text, and filled rows/tiles of the app's
/// own surfaces (Watch Now, Search, Library, Settings). The Detail screen renders over full-bleed
/// artwork and stays dark in every appearance, so it keeps its own fixed colors (`Theme.Color`)
/// instead of reading from here.
struct ThemePalette: Sendable {
    /// Full-screen page background behind a screen's content.
    let background: Color

    let primaryText: Color
    let secondaryText: Color
    let tertiaryText: Color

    /// Slightly muted heading shown above a content row (between primary and secondary in weight).
    let rowHeader: Color

    /// Filled, focusable list rows and tiles (Settings, manifest fields). `rest` is the idle fill,
    /// `focused` the lifted fill, `borderFocused` the hairline stroke drawn while focused.
    let cardRest: Color
    let cardFocused: Color
    let cardBorderFocused: Color

    /// Solid fill used by inverted controls when focused (e.g. the Trakt pill); text on top of it
    /// uses `background` so the control reads as a filled chip in either appearance.
    let accent: Color
    let destructive: Color
}

extension ThemePalette {
    /// Light appearance — mirrors Apple TV+. The app ships light-only today.
    static let light = ThemePalette(
        background: Color(red: 0.84, green: 0.85, blue: 0.87),
        primaryText: .black.opacity(0.92),
        secondaryText: .black.opacity(0.62),
        tertiaryText: .black.opacity(0.38),
        rowHeader: .black.opacity(0.70),
        cardRest: .white.opacity(0.55),
        cardFocused: .white,
        cardBorderFocused: .black.opacity(0.08),
        accent: .black.opacity(0.92),
        destructive: Color(red: 0.80, green: 0.13, blue: 0.13)
    )

    /// Dark appearance — not wired up yet. Kept here so enabling dark mode is a value swap, not a
    /// refactor; values mirror the immersive constants in `Theme.Color`.
    static let dark = ThemePalette(
        background: .black,
        primaryText: .white,
        secondaryText: .white.opacity(0.65),
        tertiaryText: .white.opacity(0.40),
        rowHeader: .white.opacity(0.80),
        cardRest: .white.opacity(0.08),
        cardFocused: .white.opacity(0.22),
        cardBorderFocused: .white.opacity(0.35),
        accent: .white,
        destructive: Color(red: 0.95, green: 0.32, blue: 0.32)
    )
}

extension EnvironmentValues {
    /// The active chrome appearance. Injected once at the app root; read with
    /// `@Environment(\.theme)`. Defaults to `.light` so previews and detached views render correctly.
    @Entry var theme: ThemePalette = .light
}
