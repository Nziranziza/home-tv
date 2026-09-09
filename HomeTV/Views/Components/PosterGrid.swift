import SwiftUI

/// A titled poster grid, shared by Search's Browse/Results set and the genre screen. Geometry
/// (260×391 posters, 40 pt gutters, 80 pt margins) matches the reference frame.
struct PosterGrid: View {
    /// How the grid's title reads: a section label above a set within a screen (Search's
    /// Browse/Results), or the page title of a screen that is nothing but this grid (a genre).
    enum TitleStyle { case sectionLabel, screen }

    let title: String
    var titleStyle: TitleStyle = .sectionLabel
    let items: [MetaPreview]
    var onSelect: (MetaPreview) -> Void
    @Environment(\.theme) private var theme

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(Theme.Search.posterSize.width), spacing: Theme.Search.posterGutter),
            count: Theme.Search.posterColumns
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Search.titleSpacing) {
                switch titleStyle {
                case .sectionLabel:
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(theme.rowHeader)
                case .screen:
                    ScreenTitle(title: title)
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Search.posterRowGap) {
                    ForEach(items) { meta in
                        ContentCard(meta: meta, sizeOverride: Theme.Search.posterSize) {
                            onSelect(meta)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Layout.horizontalMargin)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }
}
