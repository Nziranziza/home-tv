import SwiftUI

/// The last row on Watch Now: titles you've *finished*, newest first, as landscape stills you can
/// jump back into. The counterpart to `ContinueWatchingRow` at the top of the screen.
struct RecentlyWatchedRow: View {
    let items: [RecentlyWatchedItem]
    var onSelect: (RecentlyWatchedItem) -> Void = { _ in }

    /// Owned here rather than by `WatchNowView`, so the still fetches (and the re-render when they
    /// land) stay inside this row and never re-evaluate the page body or its lazy catalog rows.
    @State private var stills = EpisodeStillStore()

    private var rowHeight: CGFloat {
        Theme.Card.continueWatchingSize.height + Theme.Row.continueWatchingVerticalPadding * 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Row.headerSpacing) {
            RowHeader(title: "Recently Watched", color: Theme.WatchNow.rowHeaderColor)

            ScrollView(.horizontal) {
                LazyHStack(spacing: Theme.Row.continueWatchingCardSpacing) {
                    ForEach(items) { item in
                        RecentlyWatchedCard(item: withStill(item)) { onSelect(item) }
                    }
                }
                .padding(.horizontal, Theme.Row.contentInset)
                .padding(.vertical, Theme.Row.continueWatchingVerticalPadding)
            }
            .scrollIndicators(.hidden)
            // As in ContentRow / ContinueWatchingRow: don't clip the focused card's lift + shadow.
            .scrollClipDisabled()
            .frame(height: rowHeight)
        }
        // One vertical focus target for the whole row (see ContentRow).
        .focusSection()
        .task(id: stillsRequestKey) {
            await stills.load(for: items)
        }
    }

    /// The card's artwork, upgraded to the episode still once the show's episode list has loaded.
    private func withStill(_ item: RecentlyWatchedItem) -> RecentlyWatchedItem {
        guard let key = item.episodeKey, let still = stills.stills[key] else { return item }
        var updated = item
        updated.still = still
        return updated
    }

    /// Re-fires the still fetch only when the row's *shows* actually change — not on every re-render,
    /// and not when a still arrives (which changes the cards but not this key).
    private var stillsRequestKey: String {
        items.compactMap { $0.episodeKey == nil ? nil : $0.metaID }.joined(separator: ",")
    }
}
