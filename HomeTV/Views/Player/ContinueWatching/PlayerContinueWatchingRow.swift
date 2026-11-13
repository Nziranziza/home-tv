import SwiftUI

/// The Continue Watching tab's panel: the Watch Now cards in one row, in place of the track.
struct PlayerContinueWatchingRow: View {
    let items: [WatchHistoryItem]
    /// The card resolving its stream. The others are disabled meanwhile, so focus stays put.
    let resumingID: String?
    let focus: FocusState<PlayerFocus?>.Binding
    let onShowDetail: (WatchHistoryItem) -> Void
    let onSelect: (WatchHistoryItem) -> Void

    /// Between cards, measured against the system player.
    private static let cardSpacing: CGFloat = 40

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: Self.cardSpacing) {
                ForEach(items) { item in
                    ContinueWatchingCard(
                        item: item,
                        isResuming: resumingID == item.id,
                        showsSourceBadge: false,
                        onShowDetail: { onShowDetail(item) }
                    ) {
                        onSelect(item)
                    }
                    .disabled(resumingID != nil && resumingID != item.id)
                    .focused(focus, equals: .continueWatchingCard(item.id))
                    // The tabs sit at the far left, out of Up's reach, so Up goes back to this tab.
                    .onMoveCommand { direction in
                        if direction == .up { focus.wrappedValue = .continueWatching }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        // Cards run on past the bar's margin to the screen's edge, and lift without clipping.
        .scrollClipDisabled()
        .frame(height: Theme.Card.continueWatchingSize.height)
        .focusSection()
    }
}
