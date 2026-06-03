import Foundation

/// Raw TMDB API response types. Decoded with `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase`,
/// so snake_case JSON keys map to camelCase properties automatically.
///
/// IMPORTANT: `.convertFromSnakeCase` mangles TMDB's numeric snake keys — `iso_3166_1` becomes
/// `iso31661` and `iso_639_1` becomes `iso6391` (verified empirically). Any type touching those
/// fields declares explicit `CodingKeys` mapping to the *converted* string, not the raw JSON key.
///
/// These are deliberately partial: only the fields the app surfaces are modeled. All are
/// `Sendable` so they cross the `TMDBClient` actor boundary cleanly.

// MARK: - Find (IMDB → TMDB)

struct TMDBFindResult: Codable, Sendable {
    let movieResults: [TMDBFindItem]
    let tvResults: [TMDBFindItem]
}

struct TMDBFindItem: Codable, Sendable {
    let id: Int
}

// MARK: - Shared sub-objects

struct TMDBGenre: Codable, Sendable {
    let id: Int
    let name: String
}

struct TMDBProductionCountry: Codable, Sendable {
    let code: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case code = "iso31661"   // JSON iso_3166_1 → converted by .convertFromSnakeCase
        case name
    }
}

struct TMDBSpokenLanguage: Codable, Sendable {
    let englishName: String?
    let name: String?
    let code: String?

    enum CodingKeys: String, CodingKey {
        case englishName
        case name
        case code = "iso6391"   // JSON iso_639_1 → converted by .convertFromSnakeCase
    }
}

struct TMDBNetwork: Codable, Sendable {
    let id: Int
    let name: String
    let logoPath: String?
}

// MARK: - Credits

struct TMDBCredits: Codable, Sendable {
    let cast: [TMDBCastMember]
    let crew: [TMDBCrewMember]
}

struct TMDBCastMember: Codable, Sendable {
    let id: Int
    let name: String
    let character: String?
    let profilePath: String?
    let order: Int?
}

struct TMDBCrewMember: Codable, Sendable {
    let id: Int
    let name: String
    let job: String?
    let department: String?
}

// MARK: - Videos (trailers)

struct TMDBVideoList: Codable, Sendable {
    let results: [TMDBVideo]
}

struct TMDBVideo: Codable, Sendable {
    let site: String?
    let type: String?
    let key: String?
    let name: String?
    let official: Bool?
}

// MARK: - Images (logos / backdrops)

struct TMDBImageList: Codable, Sendable {
    let logos: [TMDBImage]?
    let backdrops: [TMDBImage]?
}

struct TMDBImage: Codable, Sendable {
    let filePath: String?
    let code: String?
    let voteAverage: Double?

    enum CodingKeys: String, CodingKey {
        case filePath
        case code = "iso6391"   // language of the artwork; nil for textless
        case voteAverage
    }
}

// MARK: - Recommendations

struct TMDBRecommendations: Codable, Sendable {
    let results: [TMDBRecommendationItem]
}

struct TMDBRecommendationItem: Codable, Sendable {
    let id: Int
    let title: String?       // movies
    let name: String?        // tv
    let mediaType: String?   // "movie" | "tv"
    let posterPath: String?
    let backdropPath: String?
}

// MARK: - Certifications

struct TMDBReleaseDatesResponse: Codable, Sendable {
    let results: [TMDBReleaseDatesByCountry]
}

struct TMDBReleaseDatesByCountry: Codable, Sendable {
    let code: String?
    let releaseDates: [TMDBReleaseDate]

    enum CodingKeys: String, CodingKey {
        case code = "iso31661"
        case releaseDates
    }
}

struct TMDBReleaseDate: Codable, Sendable {
    let certification: String?
}

struct TMDBContentRatingsResponse: Codable, Sendable {
    let results: [TMDBContentRating]
}

struct TMDBContentRating: Codable, Sendable {
    let code: String?
    let rating: String?

    enum CodingKeys: String, CodingKey {
        case code = "iso31661"
        case rating
    }
}

// MARK: - Watch providers (JustWatch via TMDB)

struct TMDBWatchProviders: Codable, Sendable {
    /// Keyed by ISO country code (e.g. "US").
    let results: [String: TMDBWatchCountry]
}

struct TMDBWatchCountry: Codable, Sendable {
    let link: String?
    let flatrate: [TMDBProvider]?   // included with a subscription
    let free: [TMDBProvider]?
    let ads: [TMDBProvider]?
    let rent: [TMDBProvider]?
    let buy: [TMDBProvider]?
}

struct TMDBProvider: Codable, Sendable {
    let providerId: Int
    let providerName: String
    let logoPath: String?
    let displayPriority: Int?
}

// MARK: - External IDs (bridge TMDB id → IMDB id for navigation)

struct TMDBExternalIDs: Codable, Sendable {
    let imdbId: String?
}

// MARK: - Movie detail

struct TMDBMovieDetail: Codable, Sendable {
    let id: Int
    let title: String?
    let overview: String?
    let genres: [TMDBGenre]?
    let voteAverage: Double?
    let runtime: Int?                       // minutes
    let status: String?
    let posterPath: String?
    let backdropPath: String?
    let productionCountries: [TMDBProductionCountry]?
    let spokenLanguages: [TMDBSpokenLanguage]?

    // append_to_response payloads
    let credits: TMDBCredits?
    let videos: TMDBVideoList?
    let images: TMDBImageList?
    let recommendations: TMDBRecommendations?
    let releaseDates: TMDBReleaseDatesResponse?
    let externalIds: TMDBExternalIDs?
}

// MARK: - TV detail

struct TMDBTVDetail: Codable, Sendable {
    let id: Int
    let name: String?
    let overview: String?
    let genres: [TMDBGenre]?
    let voteAverage: Double?
    let episodeRunTime: [Int]?              // minutes
    let status: String?
    let posterPath: String?
    let backdropPath: String?
    let productionCountries: [TMDBProductionCountry]?
    let spokenLanguages: [TMDBSpokenLanguage]?
    let networks: [TMDBNetwork]?

    // append_to_response payloads
    let credits: TMDBCredits?
    let videos: TMDBVideoList?
    let images: TMDBImageList?
    let recommendations: TMDBRecommendations?
    let contentRatings: TMDBContentRatingsResponse?
    let externalIds: TMDBExternalIDs?
}

// MARK: - Season detail

struct TMDBSeasonDetail: Codable, Sendable {
    let id: Int
    let seasonNumber: Int?
    let posterPath: String?
    let episodes: [TMDBEpisode]
}

struct TMDBEpisode: Codable, Sendable {
    let episodeNumber: Int?
    let seasonNumber: Int?
    let name: String?
    let overview: String?
    let stillPath: String?
    let runtime: Int?
    let airDate: String?
}

