import SwiftUI

/// The system-player transport bar: title and round buttons, the track, and the Info and Continue
/// Watching tabs, pinned to the bottom of the screen.
struct PlayerTransportBar: View {
    let model: PlayerModel
    let focus: FocusState<PlayerFocus?>.Binding
    let onSelect: (PlayerFocus) -> Void
    let onMove: (MoveCommandDirection) -> Void

    /// Between the tabs and the Info panel, measured against the system player.
    private static let infoPanelGap: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The Info panel takes the track's place and pushes the tabs up.
            if !model.isInfoOpen {
                PlayerTransportHeader(model: model, focus: focus, onSelect: onSelect, onMove: onMove)
                    .transition(.opacity)
            }
            PlayerTabs(focus: focus, isInfoOpen: model.isInfoOpen, onSelect: onSelect, onExitUp: model.closeInfo)
                // Down from the track lands on Info, whichever tab sits under the playhead.
                .focusBarrier(.top, isActive: focus.wrappedValue == .scrubber) { focus.wrappedValue = .info }
                .disabled(model.subtitlesMenu != nil)
                .padding(.top, 16)
            if model.isInfoOpen {
                PlayerInfoPanel(model: model, focus: focus, onSelect: onSelect)
                    .padding(.top, Self.infoPanelGap)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}
