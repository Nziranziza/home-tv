import SwiftUI

/// The Info tab's panel: the poster, the title's details and badges, and the From Beginning and Go to
/// buttons, on dark glass the width of the track.
struct PlayerInfoPanel: View {
    let model: PlayerModel
    let focus: FocusState<PlayerFocus?>.Binding
    let onSelect: (PlayerFocus) -> Void

    static let cornerRadius: CGFloat = 43
    /// The poster's inset from the panel's edge.
    static let inset: CGFloat = 22

    var body: some View {
        HStack(spacing: 0) {
            PlayerInfoPoster(url: model.titleInfo?.posterURL)
            PlayerInfoDetails(
                title: model.request.episodeLabel ?? model.request.title,
                synopsis: model.titleInfo?.synopsis,
                line: model.infoLine,
                badges: model.badges
            )
            .padding(.leading, 40)
            Spacer(minLength: 60)
            PlayerInfoButtons(type: model.request.type, canGoToDetail: model.detail != nil, focus: focus, onSelect: onSelect)
                .padding(.trailing, 26)
        }
        .padding(Self.inset)
        .frame(maxWidth: .infinity)
        .background {
            Color.clear.glassEffect(.regular, in: .rect(cornerRadius: Self.cornerRadius))
        }
        // The whole panel, so Down from the tabs at the left reaches the buttons at the right.
        .focusSection()
    }
}
