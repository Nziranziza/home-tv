import SwiftUI

// MARK: - Cast chip

/// One Cast & Crew entry: a person's name, their role/character, and an optional headshot URL.
struct CreditEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let role: String
    let imageURL: URL?
}

/// A focusable Cast & Crew avatar with the person's name and role beneath it. On focus the circular
/// headshot lifts and the labels slide down to clear it, both turning white — mirroring the focus
/// behaviour of `EpisodeCard`.
struct CastChip: View {
    let name: String
    var role: String? = nil
    /// TMDB headshot. When nil (or while loading), an initials avatar is shown instead.
    var imageURL: URL? = nil
    var action: () -> Void = {}

    @FocusState private var focused: Bool
    /// Drives the slide only, so the gap animates while the label colours snap instantly. (A moving
    /// avatar plus a fading colour at the same time reads as two separate animations.)
    @State private var lifted = false

    /// Diameter sized so six avatars (plus a sliver of the seventh) fit the detail row.
    private let avatarSize: CGFloat = 250

    var body: some View {
        VStack(spacing: lifted ? 38 : 14) {
            avatarButton
            labelBlock
        }
        .frame(width: avatarSize)
        .onChange(of: focused) { _, isFocused in
            withAnimation(.easeOut(duration: 0.25)) { lifted = isFocused }
        }
    }

    /// The circular headshot. `.buttonBorderShape(.circle)` reshapes the `.card` style's focus lift
    /// to follow the avatar, rather than drawing a square platter behind it.
    private var avatarButton: some View {
        Button(action: action) {
            avatar
                .frame(width: avatarSize, height: avatarSize)
                .clipShape(.circle)
        }
        .buttonStyle(.card)
        .buttonBorderShape(.circle)
        .focused($focused)
    }

    /// Name + role as one block. Kept as a member of this view (not a separate `View`) so its colour
    /// changes share the body's animation, like `EpisodeCard`'s `descriptionBox`. Both lines go full
    /// white on focus; the role stays muted otherwise.
    private var labelBlock: some View {
        VStack(spacing: 2) {
            Text(name)
                .font(.subheadline)
                .foregroundStyle(focused ? .white : Theme.Color.primaryText.opacity(0.9))
                .lineLimit(1)
            if let role {
                Text(role)
                    .font(.caption2)
                    .foregroundStyle(focused ? .white : Theme.Color.secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(width: avatarSize)
        .multilineTextAlignment(.center)
    }

    @ViewBuilder
    private var avatar: some View {
        if let imageURL {
            RemoteImage(url: imageURL, targetSize: CGSize(width: avatarSize, height: avatarSize), contentMode: .fill) {
                initialsAvatar
            }
        } else {
            initialsAvatar
        }
    }

    private var initialsAvatar: some View {
        Circle()
            .fill(Theme.Color.cardRest)
            .overlay {
                Text(initials)
                    .font(.title.weight(.bold))
                    .foregroundStyle(Theme.Color.primaryText.opacity(0.7))
            }
    }

    private var initials: String {
        let parts = name.split(separator: " ").compactMap { $0.first }.map(String.init)
        return parts.prefix(2).joined().uppercased()
    }
}
