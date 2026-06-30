import Foundation

/// Static TMDB genre id → name maps. The person filmography (`combined_credits`) gives each title's
/// `genre_ids` but not the genre names, so we resolve the primary one here to drive the poster card's
/// focus caption ("Movie · Action"). TMDB's genre lists are fixed and rarely change, so a baked-in map
/// avoids an extra `/genre/*/list` round-trip.
enum TMDBGenres {
    static func name(forMovie id: Int) -> String? { movie[id] }
    static func name(forTV id: Int) -> String? { tv[id] }

    /// Primary genre name for a credit's `genre_ids`, picking by the credit's media type.
    static func primaryName(ids: [Int]?, mediaType: String?) -> String? {
        guard let first = ids?.first else { return nil }
        return mediaType == "tv" ? name(forTV: first) : name(forMovie: first)
    }

    private static let movie: [Int: String] = [
        28: "Action", 12: "Adventure", 16: "Animation", 35: "Comedy", 80: "Crime",
        99: "Documentary", 18: "Drama", 10751: "Family", 14: "Fantasy", 36: "History",
        27: "Horror", 10402: "Music", 9648: "Mystery", 10749: "Romance", 878: "Science Fiction",
        10770: "TV Movie", 53: "Thriller", 10752: "War", 37: "Western"
    ]

    private static let tv: [Int: String] = [
        10759: "Action & Adventure", 16: "Animation", 35: "Comedy", 80: "Crime",
        99: "Documentary", 18: "Drama", 10751: "Family", 10762: "Kids", 9648: "Mystery",
        10763: "News", 10764: "Reality", 10765: "Sci-Fi & Fantasy", 10766: "Soap",
        10767: "Talk", 10768: "War & Politics", 37: "Western"
    ]
}
