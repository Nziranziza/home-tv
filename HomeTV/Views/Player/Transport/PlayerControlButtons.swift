import SwiftUI

/// Subtitles, Audio and Picture in Picture, above the right end of the track.
struct PlayerControlButtons: View {
    let focus: FocusState<PlayerFocus?>.Binding
    let onSelect: (PlayerFocus) -> Void

    var body: some View {
        HStack(spacing: 24) {
            PlayerRoundButton(title: "Subtitles", systemImage: "captions.bubble") { onSelect(.subtitles) }
                .focused(focus, equals: .subtitles)
            PlayerRoundButton(title: "Audio", systemImage: "waveform") { onSelect(.audio) }
                .focused(focus, equals: .audio)
            PlayerRoundButton(title: "Picture in Picture", systemImage: "pip.enter") { onSelect(.pictureInPicture) }
                .focused(focus, equals: .pictureInPicture)
        }
        .focusSection()
    }
}
