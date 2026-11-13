import SwiftUI

struct ContinueWatchingRow: View {
    let items: [WatchHistoryItem]
    /// The card resolving its stream. The others are disabled meanwhile, so focus stays put.
    var resumingID: String? = nil
    var onShowDetail: (WatchHistoryItem) -> Void = { _ in }
    var onSelect: (WatchHistoryItem) -> Void = { _ in }

    private var rowHeight: CGFloat {
        Theme.Card.continueWatchingSize.height + Theme.Row.continueWatchingVerticalPadding * 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Row.headerSpacing) {
            RowHeader(title: "Continue Watching", color: Theme.WatchNow.rowHeaderColor)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Row.continueWatchingCardSpacing) {
                    ForEach(items) { item in
                        ContinueWatchingCard(
                            item: item,
                            isResuming: resumingID == item.id,
                            onShowDetail: { onShowDetail(item) }
                        ) { onSelect(item) }
                        .disabled(resumingID != nil && resumingID != item.id)
                    }
                }
                .padding(.horizontal, Theme.Row.contentInset)
                .padding(.vertical, Theme.Row.continueWatchingVerticalPadding)
            }
            .scrollClipDisabled()
            .frame(height: rowHeight)
        }
        // One vertical focus target for the whole row (see ContentRow).
        .focusSection()
    }
}
