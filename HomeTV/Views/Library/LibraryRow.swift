import SwiftUI

/// One titled row of poster cards in the Library tab.
struct LibraryRow: View {
    let title: String
    let items: [MetaPreview]
    @Binding var selection: MetaPreview?

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Row.headerSpacing) {
            Text(title)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .padding(.horizontal, Theme.Layout.horizontalMargin)

            ScrollView(.horizontal) {
                LazyHStack(spacing: Theme.Row.posterCardSpacing) {
                    ForEach(items) { meta in
                        ContentCard(meta: meta) { selection = meta }
                    }
                }
                .padding(.horizontal, Theme.Layout.horizontalMargin)
                .padding(.vertical, Theme.Row.posterVerticalPadding)
            }
            .scrollIndicators(.hidden)
            .frame(height: Theme.Row.posterHeight)
            .scrollClipDisabled()
        }
        .focusSection()
    }
}
