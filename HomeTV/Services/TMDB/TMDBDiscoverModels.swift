import Foundation

/// A page of `/discover/movie` or `/discover/tv`.
struct TMDBDiscoverResponse: Codable, Sendable {
    let results: [TMDBDiscoverItem]
}

/// A discover result of either media type: movies fill `title`/`releaseDate`, series `name`/`firstAirDate`.
struct TMDBDiscoverItem: Codable, Sendable {
    let id: Int
    let title: String?
    let name: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let genreIds: [Int]?
    let releaseDate: String?
    let firstAirDate: String?
}

/// A title's logos and IMDB id, fetched for the channel hero.
struct TMDBTitleSummary: Codable, Sendable {
    let images: TMDBImageList?
    let externalIds: TMDBExternalIDs?
}

/// `/network/{id}`: the wordmark a channel card carries.
struct TMDBNetworkDetail: Codable, Sendable {
    let name: String?
    let logoPath: String?
}
