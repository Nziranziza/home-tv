import SwiftUI

/// The system-player transport bar: title and round buttons, the track, and the Info and Continue
/// Watching tabs, pinned to the bottom of the screen.
struct PlayerTransportBar: View {
    let model: PlayerModel
    let focus: FocusState<PlayerFocus?>.Binding
    let onSelect: (PlayerFocus) -> Void
    let onMove: (MoveCommandDirection) -> Void

    /// Episode line to show name, measured against the system player.
    private static let episodeLabelGap: CGFloat = 2.5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let episodeLabel = model.request.episodeLabel {
                Text(episodeLabel)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.leading, 4)
                    .padding(.bottom, Self.episodeLabelGap)
            }
            HStack(alignment: .center) {
                Text(model.request.title)
                    .font(.title2)
                    .bold()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    // The system player sets its text in from the track's ends and drops the title
                    // below the buttons' centre line.
                    .padding(.leading, 4)
                    .padding(.top, 12)
                Spacer(minLength: 40)
                PlayerControlButtons(focus: focus, onSelect: onSelect)
            }
            PlayerScrubberButton(model: model, focus: focus, onMove: onMove)
                .padding(.top, 32)
            PlayerTabs(focus: focus, onSelect: onSelect)
                .padding(.top, 17)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}
