import SwiftUI

/// "Related" row: TMDB recommendations when available, else the genre-catalog fallback.
struct DetailRelatedSection: View {
    let model: MetaDetailModel
    let scroll: DetailScrollState
    @Binding var relatedSelection: MetaPreview?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DetailSectionHeader(title: "Related", scroll: scroll)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 40) {
                    ForEach(model.vm.relatedItems) { item in
                        ContentCard(meta: item, sizeOverride: CGSize(width: 261, height: 392)) {
                            openRelated(item)
                        }
                    }
                }
                .padding(.horizontal, Theme.Detail.leftInset)
                .padding(.vertical, 16)
            }
            .detailRowScroll()
            .focusSection()
        }
    }

    /// Navigate to a Related item. Genre-catalog items carry a real IMDB id and navigate directly;
    /// TMDB recommendation items carry an encoded TMDB ref, resolved to an IMDB id on select (one
    /// request) so the addon-backed detail screen can load it.
    private func openRelated(_ item: MetaPreview) {
        guard let ref = TMDBRef(encodedID: item.id) else {
            relatedSelection = item
            return
        }
        Task {
            guard let imdb = await TMDBService.shared.imdbID(for: ref) else { return }
            relatedSelection = MetaPreview(
                id: imdb, type: item.type, name: item.name,
                poster: item.poster, posterShape: nil, background: item.background,
                logo: nil, description: nil, releaseInfo: nil, imdbRating: nil, genres: nil
            )
        }
    }
}
