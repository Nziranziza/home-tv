import SwiftUI

/// The system-player transport bar: title and round buttons, the track, and the Info and Continue
/// Watching tabs, pinned to the bottom of the screen.
struct PlayerTransportBar: View {
    let model: PlayerModel
    let focus: FocusState<PlayerFocus?>.Binding
    let onSelect: (PlayerFocus) -> Void
    let onMove: (MoveCommandDirection) -> Void

    /// Between the tabs and the open panel, measured against the system player.
    private static let panelGap: CGFloat = 44
    /// Lifts the cards off the bar's bottom margin, measured against the system player.
    private static let cardsBottomInset: CGFloat = 27

    var body: some View {
        let continueItems = model.continueWatchingItems
        VStack(alignment: .leading, spacing: 0) {
            // A panel takes the track's place and pushes the tabs up.
            if model.panel == nil {
                PlayerTransportHeader(model: model, focus: focus, onSelect: onSelect, onMove: onMove)
                    .transition(.opacity)
            }
            PlayerTabs(
                focus: focus,
                panel: model.panel,
                showsContinueWatching: !continueItems.isEmpty,
                onSelect: onSelect,
                onExitUp: model.closePanel
            )
            // Down from the track lands on Info, whichever tab sits under the playhead.
            .focusBarrier(.top, isActive: focus.wrappedValue == .scrubber) { focus.wrappedValue = .info }
            .disabled(model.subtitlesMenu != nil)
            .padding(.top, 16)
            switch model.panel {
            case .info:
                PlayerInfoPanel(model: model, focus: focus, onSelect: onSelect)
                    .padding(.top, Self.panelGap)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            case .continueWatching:
                PlayerContinueWatchingRow(
                    items: continueItems,
                    resumingID: model.resumer.resumingID,
                    focus: focus,
                    onShowDetail: { model.goToDetail($0.preview) },
                    onSelect: model.resume
                )
                .padding(.top, Self.panelGap)
                .padding(.bottom, Self.cardsBottomInset)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            case nil:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}
