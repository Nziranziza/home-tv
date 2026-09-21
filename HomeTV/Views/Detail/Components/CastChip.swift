import SwiftUI

// MARK: - Cast chip

/// One Cast & Crew entry: a person's name, their role/character, and an optional headshot URL.
struct CreditEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let role: String
    let imageURL: URL?
    /// TMDB person id, when known (cast from TMDB). Drives navigation into the person/cast screen;
    /// nil for name-only crew (addon director/writer) entries, which aren't tappable through.
    var personID: Int? = nil
}

/// A focusable Cast & Crew avatar with the person's name and role beneath it. On focus the circular
/// headshot lifts and the labels slide down to clear it, both turning white — mirroring the focus
/// behaviour of `EpisodeCard`.
struct CastChip: View {
    let name: String
    var role: String? = nil
    /// TMDB headshot. When nil (or while loading), an initials avatar is shown instead.
    var imageURL: URL? = nil
    /// Diameter of the circular headshot. The default fits six avatars (plus a sliver of the seventh)
    /// across the detail row.
    var avatarSize: CGFloat = 250
    /// Show the name/role block only while focused — the Search screen's Cast & Crew row, which labels
    /// just the focused headshot. The block keeps its space either way, so the row never jumps.
    var labelsOnFocusOnly: Bool = false
    /// Which surface the chip sits on, which is what its label and initials-avatar colours follow.
    var surface: Surface = .immersive
    var action: () -> Void = {}

    /// The detail screen renders over full-bleed dark artwork and fixes its text white; Search is
    /// themed chrome, so its chips resolve colours from `\.theme` instead.
    enum Surface { case immersive, themed }

    @FocusState private var focused: Bool
    @Environment(\.theme) private var theme
    /// Drives the slide only, so the gap animates while the label colours snap instantly. (A moving
    /// avatar plus a fading colour at the same time reads as two separate animations.)
    @State private var lifted = false

    var body: some View {
        VStack(spacing: lifted ? 38 : 14) {
            avatarButton
            labelBlock
                .opacity(labelsOnFocusOnly && !focused ? 0 : 1)
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
                .foregroundStyle(focused ? focusedTextColor : restTextColor)
                .lineLimit(1)
            if let role {
                Text(role)
                    .font(.caption2)
                    .foregroundStyle(focused ? focusedTextColor : secondaryTextColor)
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
            .fill(surface == .immersive ? Theme.Color.cardRest : theme.cardRest)
            .overlay {
                Text(initials)
                    .font(.title.weight(.bold))
                    .foregroundStyle(restTextColor.opacity(0.8))
            }
    }

    // MARK: - Surface colours

    private var focusedTextColor: Color {
        surface == .immersive ? .white : theme.primaryText
    }

    private var restTextColor: Color {
        surface == .immersive ? Theme.Color.primaryText.opacity(0.9) : theme.secondaryText
    }

    private var secondaryTextColor: Color {
        surface == .immersive ? Theme.Color.secondaryText : theme.tertiaryText
    }

    private var initials: String {
        let parts = name.split(separator: " ").compactMap { $0.first }.map(String.init)
        return parts.prefix(2).joined().uppercased()
    }
}
