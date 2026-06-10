import SwiftUI

enum Theme {
    enum Color {
        static let background = SwiftUI.Color.black
        static let pageBackground = SwiftUI.Color(red: 0.84, green: 0.85, blue: 0.87)

        static let cardRest = SwiftUI.Color.white.opacity(0.08)
        static let cardFocused = SwiftUI.Color.white.opacity(0.22)
        static let cardBorderFocused = SwiftUI.Color.white.opacity(0.35)

        static let primaryText = SwiftUI.Color.white
        static let secondaryText = SwiftUI.Color.white.opacity(0.65)
        static let tertiaryText = SwiftUI.Color.white.opacity(0.40)

        static let primaryTextOnLight = SwiftUI.Color.black.opacity(0.92)
        static let secondaryTextOnLight = SwiftUI.Color.black.opacity(0.62)
        static let tertiaryTextOnLight = SwiftUI.Color.black.opacity(0.38)
        static let rowHeaderOnLight = SwiftUI.Color.black.opacity(0.70)

        static let accent = SwiftUI.Color.white
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

    enum Hero {
        static let height: CGFloat = 980

        /// Target decode size for the full-bleed backdrop (tvOS renders at 1920×1080 points).
        static let backdropTargetSize = CGSize(width: 1920, height: 1080)

        static let autoAdvanceInterval: Double = 7
        static let crossfadeDuration: Double = 0.9
        /// Duration of the horizontal page-slide when the featured item changes.
        static let pageSlideDuration: Double = 0.55

        static let kenBurnsDuration: Double = 22
        // Both scale ends stay zoomed enough that the pan offset never exposes an edge of the image
        // (base must comfortably cover kenBurnsOffsetX/Y). The animation pans between the two.
        static let kenBurnsBaseScale: CGFloat = 1.08
        static let kenBurnsScale: CGFloat = 1.16
        static let kenBurnsOffsetX: CGFloat = 22
        static let kenBurnsOffsetY: CGFloat = 16

        static let horizontalPadding: CGFloat = 88
        static let bottomPadding: CGFloat = 140
        static let contentSpacing: CGFloat = 22
        static let actionRowSpacing: CGFloat = 22
        static let actionRowTopPadding: CGFloat = 6
        static let metaChipsSpacing: CGFloat = 14
        static let pageDotsBottomPadding: CGFloat = 60
        static let pageDotsSpacing: CGFloat = 8
        static let pageDotSize: CGFloat = 8
        static let pageDotActiveWidth: CGFloat = 22
        static let pageDotsMaxVisible: Int = 9

        static let buttonHeight: CGFloat = 66
        static let primaryButtonHorizontalPadding: CGFloat = 44

        static let sourceBadgeSize: CGFloat = 30

        static let titleMaxWidth: CGFloat = 1100
        static let logoMaxWidth: CGFloat = 700
        static let logoMaxHeight: CGFloat = 200
        static let taglineMaxWidth: CGFloat = 1000
    }

    enum WatchNow {
        static let interRowSpacing: CGFloat = 48
        static let bottomPadding: CGFloat = 100
    }

    /// Search screen — the keyboard, query header and "Press ⏯…" hint are the native tvOS
    /// `.searchable` UI, so only the Browse grid's geometry lives here. Card size, gutter and side
    /// margin were measured from the reference frame (`ignore/search.png`, 1920×1080).
    enum Search {
        static let contentInset: CGFloat = 80
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

    /// Horizontal rows of cards (catalogs, Continue Watching). `contentInset` matches
    /// `Hero.horizontalPadding` so every row and the hero share one left gutter.
    enum Row {
        static let contentInset: CGFloat = 88

        static let posterHeight: CGFloat = 422
        static let posterVerticalPadding: CGFloat = 16
        static let posterCardSpacing: CGFloat = 36

        static let landscapeHeight: CGFloat = 360
        static let landscapeVerticalPadding: CGFloat = 32
        static let landscapeCardSpacing: CGFloat = 28

        // Tight header→cards spacing, shared by every row (matches Continue Watching).
        static let headerSpacing: CGFloat = 6
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

        var body: some View {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.rowHorizontal)
                .padding(.vertical, Theme.Spacing.rowVertical)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(isFocused ? Theme.Color.cardFocused : Theme.Color.cardRest)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .stroke(isFocused ? Theme.Color.cardBorderFocused : .clear, lineWidth: 2)
                )
                .scaleEffect(configuration.isPressed ? 0.97 : (isFocused ? 1.015 : 1.0))
                .animation(.easeInOut(duration: 0.18), value: isFocused)
                .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.Color.primaryText)
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(Theme.Color.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }
}

struct ScreenTitle: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(Theme.Color.primaryText)
            if let subtitle {
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(Theme.Color.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 12)
    }
}

struct RowHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.Color.rowHeaderOnLight)
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(Theme.Color.tertiaryTextOnLight)
            }
        }
        .padding(.horizontal, Theme.Row.contentInset)
    }
}
