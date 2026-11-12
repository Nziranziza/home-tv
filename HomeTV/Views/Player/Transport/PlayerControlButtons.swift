import SwiftUI

/// Subtitles, Audio and Picture in Picture, above the right end of the track. The Subtitles menu opens
/// above its button; while it's open the buttons step aside so focus stays in the menu.
struct PlayerControlButtons: View {
    let model: PlayerModel
    let focus: FocusState<PlayerFocus?>.Binding
    let onSelect: (PlayerFocus) -> Void

    /// Between the menu and the top of its button.
    private static let menuGap: CGFloat = 21
    private static let spacing: CGFloat = 24

    var body: some View {
        let isMenuOpen = model.subtitlesMenu != nil
        HStack(spacing: Self.spacing) {
            PlayerRoundButton(title: "Subtitles", systemImage: "captions.bubble", isHighlighted: isMenuOpen) {
                onSelect(.subtitles)
            }
            .focused(focus, equals: .subtitles)
            .disabled(isMenuOpen)
            PlayerRoundButton(title: "Audio", systemImage: "waveform") { onSelect(.audio) }
                .focused(focus, equals: .audio)
                .disabled(isMenuOpen)
            PlayerRoundButton(title: "Picture in Picture", systemImage: "pip.enter") { onSelect(.pictureInPicture) }
                .focused(focus, equals: .pictureInPicture)
                .disabled(isMenuOpen)
        }
        .focusSection()
        // Outside the focus section: the panel sits above the row's frame, and inside the section Up
        // couldn't move between its rows. Trailing edge lined up with the Subtitles button.
        .overlay(alignment: .bottomTrailing) {
            if let page = model.subtitlesMenu {
                SubtitlesMenu(model: model, page: page)
                    .padding(.bottom, PlayerRoundButton.diameter + Self.menuGap)
                    .padding(.trailing, 2 * (PlayerRoundButton.diameter + Self.spacing))
                    .transition(.opacity)
            }
        }
    }
}
