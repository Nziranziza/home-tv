import SwiftUI

/// The Browse by Genre row. Its cards are destinations: selecting one pushes the genre screen rather
/// than a title's detail page. Renders nothing when no enabled addon can be browsed by genre.
struct BrowseByGenreRow: View {
    var onSelect: (Genre) -> Void = { _ in }

    /// Owned here, as in `RecentlyWatchedRow`, so the artwork fetches never re-render the page body.
    @State private var model = BrowseByGenreModel()

    private var rowHeight: CGFloat { Theme.Row.posterHeight }

    var body: some View {
        let genres = model.genres
        if !genres.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Row.headerSpacing) {
                RowHeader(title: "Browse by Genre", color: Theme.WatchNow.rowHeaderColor)

                ScrollView(.horizontal) {
                    LazyHStack(spacing: Theme.Row.posterCardSpacing) {
                        ForEach(genres) { genre in
                            GenreTile(genre: genre, artworkURL: model.artworkURL(for: genre)) {
                                onSelect(genre)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Row.contentInset)
                    .padding(.vertical, Theme.Row.posterVerticalPadding)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .frame(height: rowHeight)
            }
            .focusSection()
            .task(id: model.artworkRequestKey) {
                await model.loadArtwork()
            }
        }
    }
}
