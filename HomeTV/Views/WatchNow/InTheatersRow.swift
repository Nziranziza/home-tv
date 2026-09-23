import SwiftUI

/// The In Theaters & At Home row: what is in cinemas right now, and what has just reached buy-or-rent,
/// as showcase-sized key art. The one non-personal row on Watch Now that isn't an addon catalog —
/// nothing in an addon manifest carries a release window, so `TMDBService.theatricalItems()` sources it
/// and the cards bridge back to the addon detail path on select.
///
/// Same skeleton as `RecentlyWatchedRow`, with one addition: it shows placeholder cards until the
/// source answers, so it takes its space immediately rather than shoving the catalog rows down later.
struct InTheatersRow: View {
    var onSelect: (MetaPreview) -> Void = { _ in }

    /// Owned here, as in `RecentlyWatchedRow`, so the fetch never re-renders the page body.
    @State private var model = InTheatersModel()
    /// True while a card's IMDB lookup is in flight — see `select(_:)`.
    @State private var isSelecting = false

    var body: some View {
        if model.isVisible {
            VStack(alignment: .leading, spacing: Theme.Row.headerSpacing) {
                RowHeader(title: "In Theaters & At Home", color: Theme.WatchNow.rowHeaderColor)

                ScrollView(.horizontal) {
                    LazyHStack(spacing: Theme.Row.showcaseCardSpacing) {
                        ForEach(model.items) { item in
                            InTheatersCard(item: item) { select(item) }
                        }
                        ForEach(model.placeholderSlots, id: \.self) { _ in
                            InTheatersPlaceholderCard()
                        }
                    }
                    .padding(.horizontal, Theme.Row.contentInset)
                    .padding(.vertical, Theme.Row.showcaseVerticalPadding)
                }
                .scrollIndicators(.hidden)
                // As in ContentRow / RecentlyWatchedRow: don't clip the focused card's lift + shadow,
                // which on a card this size overlaps its neighbour.
                .scrollClipDisabled()
                .frame(height: Theme.Row.showcaseHeight)
            }
            // One vertical focus target for the whole row (see ContentRow).
            .focusSection()
            .task { await model.load() }
        }
    }

    /// A card's id is a TMDB ref, so the IMDB id the detail screen needs is fetched here rather than
    /// up front — one request, only for the title actually chosen.
    ///
    /// One at a time: the lookup is a round trip, so without the guard a viewer who presses Select on a
    /// second card while the first is still resolving would push two details, in whichever order the
    /// two requests happened to finish.
    private func select(_ item: TheatricalItem) {
        guard !isSelecting else { return }
        isSelecting = true
        Task {
            let meta = await model.resolved(item)
            isSelecting = false
            guard let meta else { return }
            onSelect(meta)
        }
    }
}
