import SwiftUI

/// A titled poster grid for the genre screen. Geometry (260×391 posters, 40 pt gutters, 80 pt margins)
/// matches the reference frame; the margins come from the tvOS safe area, not padding, since six
/// columns already fill the safe width and extra padding widens the screen past it (#54).
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
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }
}
