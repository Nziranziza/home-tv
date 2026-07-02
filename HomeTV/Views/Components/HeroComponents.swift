import SwiftUI

// Shared hero building blocks used by BOTH the home hero (`HeroOverlay`) and the detail hero
// (`MetaDetailView`): the source badge, rating badge, metadata chip row, and the action buttons.

// MARK: - Source badge

/// The app's source badge ("HT"), shown on hero chips and Continue Watching cards.
struct HomeTVSourceBadge: View {
    var body: some View {
        Text("HT")
            .font(.caption2.weight(.heavy))
            .foregroundStyle(.white.opacity(0.92))
            .frame(width: Theme.Hero.sourceBadgeSize, height: Theme.Hero.sourceBadgeSize)
            .background(
                Circle().fill(.white.opacity(0.18))
            )
            .overlay(
                Circle().stroke(.white.opacity(0.3), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Rating badge

/// Small outlined badge for a rating, e.g. "PG-13", "TV-MA", or "IMDb 9.5".
struct RatingBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            // Tight padding so the thin outline hugs the small rating text (e.g. IMDb 7.7 / TV-MA).
            .padding(.horizontal, 2)
            .padding(.vertical, 1)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(.white.opacity(0.55), lineWidth: 1)
            )
            .foregroundStyle(.white.opacity(0.9))
    }
}

// MARK: - Genre normalization

extension Array where Element == String {
    /// Normalize genre entries for display. Addons/TMDB sometimes deliver a title's genres as one
    /// comma-joined string ("Comedy, Family") rather than separate entries; split them into individual,
    /// trimmed genres so both heroes render them as separate " · "-joined chips, not a comma in one chip.
    func splitGenres() -> [String] {
        flatMap { $0.split(separator: ",").map(String.init) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Meta chip row

/// Hero metadata line: source badge, then `parts` joined by " · ", then an optional trailing rating
/// badge. Used by the home hero and the detail hero (the detail uses a larger font).
struct MetaChipRow: View {
    /// The leading mark before the metadata. `.source` is the app's HT badge (home hero); `.provider`
    /// shows a streaming-provider logo when one is supplied, or nothing when nil (detail hero, à la
    /// Apple TV+ — no badge when the title isn't on a known provider).
    enum LeadingBadge {
        case source
        case provider(URL?)
    }

    let parts: [String]
    var trailingBadge: String? = nil
    var font: Font = Theme.Hero.chipFont
    var leading: LeadingBadge = .source

    var body: some View {
        HStack(spacing: Theme.Hero.metaChipsSpacing) {
            LeadingBadgeView(leading: leading)
            HStack(spacing: 0) {
                ForEach(Array(parts.enumerated()), id: \.offset) { index, value in
                    if index > 0 {
                        Text(" · ")
                            .font(font)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Text(value)
                        .font(font)
                        .foregroundStyle(.white)
                }
            }
            if let trailingBadge {
                RatingBadge(text: trailingBadge)
            }
        }
    }
}

/// The metadata row's leading mark: the app's HT source badge, or a streaming-provider/network logo
/// (and nothing when there's no known provider).
private struct LeadingBadgeView: View {
    let leading: MetaChipRow.LeadingBadge

    var body: some View {
        switch leading {
        case .source:
            HomeTVSourceBadge()
        case .provider(let url):
            if let url {
                ProviderBadge(url: url)
            }
            // nil → no badge at all (matches Apple TV+ when there's no known provider)
        }
    }
}

/// A streaming-provider logo shown in the metadata row's leading slot — a small rounded square
/// (provider logos are square artwork), sized to match the source badge.
struct ProviderBadge: View {
    let url: URL

    private var size: CGFloat { Theme.Hero.sourceBadgeSize }

    var body: some View {
        RemoteImage(url: url, targetSize: CGSize(width: size, height: size), contentMode: .fit) {
            Color.white.opacity(0.12)
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.22))
        .accessibilityHidden(true)
    }
}

// MARK: - Hero description

/// The hero logline / synopsis, shared by the Watch Now hero and the Detail hero so the description
/// reads identically in both. All of its styling — size, dimming, line spacing, clamp, and wrap width —
/// lives on `Theme.Hero`, so a change there moves both heroes at once.
struct HeroDescription: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Hero.descriptionFont)
            .foregroundStyle(.white.opacity(Theme.Hero.descriptionOpacity))
            .lineSpacing(Theme.Hero.descriptionLineSpacing)
            .lineLimit(Theme.Hero.descriptionLineLimit)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: Theme.Hero.descriptionMaxWidth, alignment: .leading)
    }
}

// MARK: - Hero title

/// The hero title: the title's logo art when it has one — aspect-fit and pinned bottom-leading so it
/// sits flush at the text gutter — otherwise the `fallback` wordmark (also shown while the logo loads).
/// Shared by the Watch Now hero and the Detail hero; each passes its own logo box size and whether to
/// drop a shadow (Watch Now lifts the logo off its bright trailer; the Detail hero doesn't).
///
/// Any left/top inset you see on a given logo is transparent padding baked into the source PNG — the art
/// is left-aligned here, so the padding is the artwork's own, not a layout offset.
struct HeroTitleArt<Fallback: View>: View {
    let logoURL: URL?
    let accessibilityName: String
    let maxWidth: CGFloat
    let maxHeight: CGFloat
    var shadow: Bool = false
    @ViewBuilder var fallback: () -> Fallback

    var body: some View {
        if let logoURL {
            RemoteImage(
                url: logoURL,
                targetSize: CGSize(width: maxWidth, height: maxHeight),
                contentMode: .fit
            ) {
                fallback()
            }
            .frame(maxWidth: maxWidth, maxHeight: maxHeight, alignment: .bottomLeading)
            .shadow(color: .black.opacity(shadow ? 0.5 : 0), radius: shadow ? 10 : 0, y: shadow ? 4 : 0)
            .accessibilityLabel(accessibilityName)
        } else {
            fallback()
        }
    }
}

// MARK: - Hero action buttons

/// Primary hero action — a white pill (e.g. "Play").
struct HeroPlayButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 30, weight: .semibold))
            .padding(.horizontal, Theme.Hero.primaryButtonHorizontalPadding)
            .frame(height: Theme.Hero.buttonHeight)
        }
        .buttonStyle(HeroPlayButtonStyle())
    }
}

/// Circular icon hero action — e.g. +, info, share, chevron.
struct HeroCircleButton: View {
    let icon: String
    let accessibilityLabel: String
    /// When true the control shows no resting platter — just the bare glyph — and only forms the circle
    /// on focus. Matches Apple TV's Watch Now, where the trailing carousel chevron is a bare `>` while
    /// the +/info controls sit on faint dark circles.
    var bare: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .semibold))
                .frame(width: Theme.Hero.buttonHeight, height: Theme.Hero.buttonHeight)
        }
        .buttonStyle(HeroCircleButtonStyle(bare: bare))
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct HeroPlayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .foregroundStyle(.black)
                .background(Capsule(style: .continuous).fill(Color.white))
                .scaleEffect(configuration.isPressed ? 0.97 : (isFocused ? 1.06 : 1.0))
                .shadow(color: .black.opacity(isFocused ? 0.45 : 0.0), radius: 22, y: 12)
                .animation(.easeInOut(duration: 0.18), value: isFocused)
        }
    }
}

private struct HeroCircleButtonStyle: ButtonStyle {
    var bare: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, bare: bare)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let bare: Bool
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .foregroundStyle(isFocused ? .black : .white)
                // Focused: solid white circle. Unfocused: a dark near-black glass circle, or — for a
                // `bare` control (the carousel chevron) — nothing, so only the glyph shows at rest.
                .background(
                    isFocused
                        ? Color.white
                        : (bare ? Color.clear : Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.85)),
                    in: .circle
                )
                .scaleEffect(configuration.isPressed ? 0.95 : (isFocused ? 1.08 : 1.0))
                .shadow(color: .black.opacity(isFocused ? 0.45 : 0.0), radius: 14, y: 8)
                .animation(.easeInOut(duration: 0.18), value: isFocused)
        }
    }
}
