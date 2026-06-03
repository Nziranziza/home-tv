import SwiftUI

// Shared hero building blocks used by BOTH the home hero (`HeroShelf`) and the detail hero
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
            .font(.caption.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(.white.opacity(0.55), lineWidth: 1)
            )
            .foregroundStyle(.white.opacity(0.9))
    }
}

// MARK: - Meta chip row

/// Hero metadata line: source badge, then `parts` joined by " · ", then an optional trailing rating
/// badge. Used by the home hero and the detail hero (the detail uses a larger font).
struct MetaChipRow: View {
    let parts: [String]
    var trailingBadge: String? = nil
    var font: Font = .callout

    var body: some View {
        HStack(spacing: Theme.Hero.metaChipsSpacing) {
            HomeTVSourceBadge()
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .semibold))
                .frame(width: Theme.Hero.buttonHeight, height: Theme.Hero.buttonHeight)
        }
        .buttonStyle(HeroCircleButtonStyle())
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
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .foregroundStyle(isFocused ? .black : .white)
                .background(
                    // Dark near-black glass when unfocused (the backdrop barely shows through), solid
                    // white when focused.
                    Circle().fill(isFocused ? Color.white : Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.85))
                )
                .scaleEffect(configuration.isPressed ? 0.95 : (isFocused ? 1.08 : 1.0))
                .shadow(color: .black.opacity(isFocused ? 0.45 : 0.0), radius: 14, y: 8)
                .animation(.easeInOut(duration: 0.18), value: isFocused)
        }
    }
}
