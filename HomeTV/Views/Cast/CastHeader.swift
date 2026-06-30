import SwiftUI

/// The cast screen header: a circular headshot beside the person's name and a three-line biography
/// that tail-truncates with an inline bold MORE cue. The whole block is centered horizontally, as on
/// Apple's person page. Selecting the biography expands it into a full popover.
struct CastHeader: View {
    let name: String
    let biography: String?
    let profileURL: URL?
    let onExpandBio: () -> Void

    private let avatarSize: CGFloat = 230
    private let columnWidth: CGFloat = 860

    var body: some View {
        HStack(alignment: .top, spacing: 40) {
            avatar
            VStack(alignment: .leading, spacing: 16) {
                Text(name)
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let biography, !biography.isEmpty {
                    BioButton(text: biography, width: columnWidth, action: onExpandBio)
                }
            }
            .frame(width: columnWidth, alignment: .leading)
            .padding(.top, 28)
        }
        .frame(maxWidth: .infinity)     // center the headshot + text block
        .padding(.top, CastLayout.headerTopPadding)
    }

    private var avatar: some View {
        RemoteImage(url: profileURL,
                    targetSize: CGSize(width: avatarSize, height: avatarSize),
                    contentMode: .fill) {
            Circle().fill(Theme.Color.cardRest)
        }
        .frame(width: avatarSize, height: avatarSize)
        .clipShape(.circle)
    }
}

/// The focusable biography. At rest it's plain truncated text aligned with the name; on focus a frosted
/// rounded panel bleeds outward behind it (the text never shifts), matching the reference. Selecting it
/// runs `action` to present the full-bio popover.
private struct BioButton: View {
    let text: String
    let width: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            InfoValueText(value: text, lineLimit: 3, fontSize: 28, palette: .castBio)
                .frame(width: width, alignment: .leading)
        }
        .buttonStyle(BioButtonStyle())
    }
}

/// Plain text at rest, a frosted highlight panel on focus. The panel is drawn as a negative-inset
/// background so the text stays put (aligned with the name) whether or not it's focused.
struct BioButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    private struct StyleBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.white.opacity(isFocused ? 0.12 : 0))
                        .padding(.horizontal, -20)
                        .padding(.vertical, -14)
                }
                .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
                .animation(.easeOut(duration: 0.18), value: isFocused)
        }
    }
}

extension InfoPalette {
    /// The header biography: light value text with a slightly brighter bold MORE, over the dark page.
    static let castBio = InfoPalette(
        title: .white,
        label: .white.opacity(0.5),
        value: Color(white: 0.78),
        more: Color(white: 0.78),
        badge: .white.opacity(0.85),
        accessory: .white.opacity(0.78)
    )
}
