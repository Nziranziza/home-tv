import SwiftUI

// MARK: - Cast chip

/// Focus treatment for a cast chip — lifts and brightens the avatar (so the section is reachable
/// by the focus engine and matches Apple's focusable cast row).
struct CastChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .brightness(isFocused ? 0.12 : 0)
                .scaleEffect(configuration.isPressed ? 0.97 : (isFocused ? 1.08 : 1.0))
                .animation(.easeOut(duration: 0.18), value: isFocused)
        }
    }
}

/// One Cast & Crew entry: a person's name, their role/character, and an optional headshot URL.
struct CreditEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let role: String
    let imageURL: URL?
}

struct CastChip: View {
    let name: String
    var role: String? = nil
    /// TMDB headshot. When nil (or while loading), an initials avatar is shown instead.
    var imageURL: URL? = nil

    var body: some View {
        VStack(spacing: 12) {
            avatar
                .frame(width: 140, height: 140)
                .clipShape(.circle)
            VStack(spacing: 2) {
                Text(name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Theme.Color.primaryText.opacity(0.9))
                    .lineLimit(1)
                if let role {
                    Text(role)
                        .font(.caption)
                        .foregroundStyle(Theme.Color.secondaryText)
                        .lineLimit(1)
                }
            }
            .frame(width: 160)
            .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let imageURL {
            RemoteImage(url: imageURL, targetSize: CGSize(width: 140, height: 140), contentMode: .fill) {
                initialsAvatar
            }
        } else {
            initialsAvatar
        }
    }

    private var initialsAvatar: some View {
        Circle()
            .fill(Theme.Color.cardRest)
            .overlay(
                Text(initials)
                    .font(.title.weight(.bold))
                    .foregroundStyle(Theme.Color.primaryText.opacity(0.7))
            )
    }

    private var initials: String {
        let parts = name.split(separator: " ").compactMap { $0.first }.map(String.init)
        return parts.prefix(2).joined().uppercased()
    }
}
