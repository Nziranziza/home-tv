import Foundation

/// One row of a channel screen, as TMDB discover queries against that channel's provider.
struct ChannelShelf: Identifiable, Hashable, Sendable {
    enum Media: String, Sendable { case movie, tv }

    enum Order: Hashable, Sendable {
        case popular
        case topRated
        /// Released within the last `days`, most popular first.
        case recent(days: Int)
    }

    let id: String
    let title: String
    let media: [Media]
    let order: Order
    var genreID: Int?

    static let topTen = ChannelShelf(id: "top", title: "Top 10", media: [.tv, .movie], order: .popular)

    /// The rows under Top 10, in screen order.
    static let rows: [ChannelShelf] = [
        ChannelShelf(id: "popular-tv", title: "Popular TV Shows", media: [.tv], order: .popular),
        ChannelShelf(id: "popular-movies", title: "Popular Movies", media: [.movie], order: .popular),
        ChannelShelf(id: "new", title: "New Releases", media: [.tv, .movie], order: .recent(days: 90)),
        ChannelShelf(id: "top-rated-tv", title: "Top Rated TV Shows", media: [.tv], order: .topRated),
        ChannelShelf(id: "top-rated-movies", title: "Top Rated Movies", media: [.movie], order: .topRated),
        ChannelShelf(id: "comedy", title: "Comedy", media: [.tv, .movie], order: .popular, genreID: 35),
        ChannelShelf(id: "drama", title: "Drama", media: [.tv, .movie], order: .popular, genreID: 18),
        ChannelShelf(id: "crime", title: "Crime", media: [.tv, .movie], order: .popular, genreID: 80),
        ChannelShelf(id: "documentary", title: "Documentaries", media: [.tv, .movie], order: .popular, genreID: 99),
        ChannelShelf(id: "animation", title: "Animation", media: [.tv, .movie], order: .popular, genreID: 16),
        ChannelShelf(id: "family", title: "Family", media: [.tv, .movie], order: .popular, genreID: 10751)
    ]

    /// Discover parameters for one media type on one provider. `today` pins the recent window.
    func parameters(media: Media, providerID: Int, region: String, today: Date) -> [String: String] {
        var parameters = [
            "watch_region": region,
            "with_watch_providers": String(providerID),
            "include_adult": "false"
        ]
        if let genreID { parameters["with_genres"] = String(genreID) }
        switch order {
        case .popular:
            parameters["sort_by"] = "popularity.desc"
            parameters["vote_count.gte"] = "50"
        case .topRated:
            parameters["sort_by"] = "vote_average.desc"
            parameters["vote_count.gte"] = "300"
        case .recent(let days):
            let dateKey = media == .movie ? "primary_release_date" : "first_air_date"
            parameters["sort_by"] = "popularity.desc"
            parameters["vote_count.gte"] = "10"
            parameters["\(dateKey).gte"] = TMDBConfig.day(TMDBConfig.date(days, daysBefore: today))
            parameters["\(dateKey).lte"] = TMDBConfig.day(today)
        }
        return parameters
    }
}
