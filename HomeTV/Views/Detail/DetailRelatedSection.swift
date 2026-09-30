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
                .detailRowContentPadding(Theme.Detail.posterRowPadding)
            }
            .detailRowScroll()
            .focusSection()
        }
    }

    private func openRelated(_ item: MetaPreview) {
        Task {
            if let resolved = await Self.resolved(item) { relatedSelection = resolved }
        }
    }

    /// A Related item ready to open. Genre-catalog items carry a real IMDB id and open as they are;
    /// TMDB recommendation items carry an encoded TMDB ref, resolved to an IMDB id (one request) so the
    /// addon-backed detail screen can load it.
    static func resolved(_ item: MetaPreview) async -> MetaPreview? {
        guard let ref = TMDBRef(encodedID: item.id) else { return item }
        guard let imdb = await TMDBService.shared.imdbID(for: ref) else { return nil }
        return MetaPreview(
            id: imdb, type: item.type, name: item.name,
            poster: item.poster, posterShape: nil, background: item.background,
            logo: nil, description: nil, releaseInfo: nil, imdbRating: nil, genres: nil
        )
    }
}
