import SwiftUI

/// The Library tab's body: the saved and in-progress rows, or the empty state when there is neither.
///
/// A separate `View` rather than a computed property on `LibraryView`, so SwiftUI re-evaluates only
/// this when the rows change.
struct LibraryContent: View {
    let continueItems: [MetaPreview]
    let watchlistItems: [MetaPreview]
    @Binding var selection: MetaPreview?

    var body: some View {
        if continueItems.isEmpty && watchlistItems.isEmpty {
            LibraryEmptyState()
        } else {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 48) {
                    ScreenTitle(title: "Library")
                        .padding(.horizontal, Theme.Layout.horizontalMargin)

                    if !continueItems.isEmpty {
                        LibraryRow(title: "Continue Watching", items: continueItems, selection: $selection)
                    }
                    if !watchlistItems.isEmpty {
                        LibraryRow(title: "Watchlist", items: watchlistItems, selection: $selection)
                    }
                }
                .padding(.vertical, 60)
            }
            .scrollIndicators(.hidden)
            .pageHorizontalInsets()
        }
    }
}
