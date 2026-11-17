import SwiftUI

/// The focus target over Up Next's corner video. The video itself draws the focus growth; selecting it
/// returns the video to full screen.
struct UpNextVideoButton: View {
    let model: PlayerModel
    let focus: FocusState<PlayerFocus?>.Binding

    var body: some View {
        Button(action: model.dismissUpNext) {
            Color.clear
                .frame(width: UpNextLayout.videoSize.width, height: UpNextLayout.videoSize.height)
        }
        .buttonStyle(PlayerSurfaceButtonStyle())
        .focused(focus, equals: .upNextVideo)
        .accessibilityLabel("Return to Full Screen")
        .onMoveCommand { direction in
            if direction == .down || direction == .left { focus.wrappedValue = .upNextNextEpisode }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, UpNextLayout.videoInset.height)
        .padding(.trailing, UpNextLayout.videoInset.width)
    }
}
