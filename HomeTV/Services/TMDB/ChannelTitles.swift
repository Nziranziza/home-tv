import Foundation

/// Pure mapping from TMDB discover results to the previews a channel screen shows.
enum ChannelTitles {
    static let topTenLimit = 10
    static let heroLimit = 6

    static func topTen(_ titles: [MetaPreview]) -> [MetaPreview] {
        Array(titles.prefix(topTenLimit))
    }

    /// A card needs a poster and a name; anything without both is dropped.
    static func preview(from item: TMDBDiscoverItem, media: ChannelShelf.Media) -> MetaPreview? {
        let name = (media == .movie ? item.title : item.name)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty,
              let poster = TMDBConfig.imageURL(path: item.posterPath, size: .w500) else { return nil }
        let date = media == .movie ? item.releaseDate : item.firstAirDate
        let genres = (item.genreIds ?? []).compactMap {
            media == .movie ? TMDBGenres.name(forMovie: $0) : TMDBGenres.name(forTV: $0)
        }
        return MetaPreview(
            id: TMDBRef(mediaType: media.rawValue, id: item.id).encoded,
            type: media == .movie ? "movie" : "series",
            name: name,
            poster: poster.absoluteString,
            posterShape: nil,
            background: TMDBConfig.imageURL(path: item.backdropPath, size: .w1280)?.absoluteString,
            logo: nil,
            description: item.overview?.isEmpty == false ? item.overview : nil,
            releaseInfo: date.flatMap { $0.count >= 4 ? String($0.prefix(4)) : nil },
            imdbRating: nil,
            genres: genres
        )
    }

    /// Round-robins the pages so neither media type crowds out the other, dropping repeats.
    static func interleave(_ pages: [[MetaPreview]]) -> [MetaPreview] {
        var merged: [MetaPreview] = []
        var seen = Set<String>()
        for index in 0..<(pages.map(\.count).max() ?? 0) {
            for page in pages where index < page.count {
                if seen.insert(page[index].id).inserted { merged.append(page[index]) }
            }
        }
        return merged
    }

    /// An English logo if there is one, else a textless one, best rated first.
    static func preferredLogoPath(_ images: TMDBImageList?) -> String? {
        let logos = (images?.logos ?? []).filter { $0.filePath != nil }
        let ranked = logos.sorted { ($0.voteAverage ?? 0) > ($1.voteAverage ?? 0) }
        return (ranked.first { $0.code == "en" } ?? ranked.first { $0.code == nil })?.filePath
    }

    /// The preview re-keyed to its IMDB id, which the hero's Play and Info need, with its title logo.
    static func heroPreview(_ preview: MetaPreview, imdbID: String, logo: URL?) -> MetaPreview {
        MetaPreview(
            id: imdbID,
            type: preview.type,
            name: preview.name,
            poster: preview.poster,
            posterShape: nil,
            background: preview.background,
            logo: logo?.absoluteString,
            description: preview.description,
            releaseInfo: preview.releaseInfo,
            imdbRating: nil,
            genres: preview.genres
        )
    }
}
