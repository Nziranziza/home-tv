import Foundation

enum TMDBClientError: Error, LocalizedError {
    case notConfigured
    case invalidURL
    case http(status: Int)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "TMDB API key is not configured."
        case .invalidURL: "Could not build a TMDB request URL."
        case .http(let status): "TMDB returned HTTP \(status)."
        case .decoding(let error): "Failed to decode TMDB response: \(error.localizedDescription)"
        case .transport(let error): "Network error: \(error.localizedDescription)"
        }
    }
}

/// Thin async wrapper over the TMDB v3 REST API, mirroring `TraktClient`/`StremioClient`'s actor +
/// ephemeral-session shape. It knows nothing about app state — it builds signed (`api_key`) requests,
/// performs them, and decodes. All higher-level logic (caching, IMDB gating, merge into `Enrichment`)
/// lives in `TMDBService`.
actor TMDBClient {
    static let shared = TMDBClient()

    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 10
            config.timeoutIntervalForResource = 20
            config.waitsForConnectivity = false
            self.session = URLSession(configuration: config)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    // MARK: - Endpoints

    /// Resolve an IMDB id (`tt…`) to TMDB movie/tv results.
    func find(imdbID: String) async throws -> TMDBFindResult {
        try await get(["find", imdbID], extra: ["external_source": "imdb_id"])
    }

    /// Movie details bundled with credits/videos/images/recommendations/release_dates/external_ids.
    func movie(id: Int) async throws -> TMDBMovieDetail {
        try await get(["movie", String(id)], extra: [
            "append_to_response": "credits,videos,images,recommendations,release_dates,external_ids"
        ])
    }

    /// TV details bundled with credits/videos/images/recommendations/content_ratings/external_ids.
    func tv(id: Int) async throws -> TMDBTVDetail {
        try await get(["tv", String(id)], extra: [
            "append_to_response": "credits,videos,images,recommendations,content_ratings,external_ids"
        ])
    }

    /// Person details (biography + headshot) bundled with their full movie/TV filmography and
    /// external ids — drives the cast/crew screen reached from the Cast & Crew row.
    func person(id: Int) async throws -> TMDBPersonDetail {
        try await get(["person", String(id)], extra: [
            "append_to_response": "combined_credits,external_ids"
        ])
    }

    /// People matching a free-text query — the Cast & Crew section of the Search screen.
    func searchPeople(query: String) async throws -> TMDBPersonSearchResponse {
        try await get(["search", "person"], extra: ["query": query, "include_adult": "false"])
    }

    /// Per-season episode metadata (runtime/stills/overviews) and the season poster.
    func season(tvID: Int, season: Int) async throws -> TMDBSeasonDetail {
        try await get(["tv", String(tvID), "season", String(season)])
    }

    /// Where the title can be watched (JustWatch data), grouped by country then availability type.
    func watchProviders(mediaType: String, id: Int) async throws -> TMDBWatchProviders {
        try await get([mediaType, String(id), "watch", "providers"])
    }

    /// Movies whose release of one of `releaseTypes` in `region` falls inside a date window, most
    /// popular first and carrying at least `minimumVotes` ratings.
    ///
    /// `release_date.gte`/`.lte` filter the *regional* release of those types, so the window asks the
    /// question and the types give the answer: the theatrical types return what is in cinemas, the
    /// digital/physical ones what has reached buy-or-rent. That is also how the In Theaters row tells a
    /// just-landed title from one that has been out a while — same call, a different window.
    ///
    /// `vote_count.gte` is what keeps the long tail out. `sort_by=popularity.desc` will rank a regional
    /// title with three ratings above a wide release, and popularity alone cannot tell them apart; this
    /// is why `/movie/now_playing` is not used for the theatrical window, as it takes no filters at all.
    /// `monetizationTypes` narrows the results to titles you can actually pay for that way in `region`
    /// (JustWatch data, e.g. `rent|buy`). A release type says a title was *published* digitally, which
    /// is not the same claim: a subscription-only premiere has a digital release and nothing to buy.
    func moviesReleased(
        region: String,
        releaseTypes: String,
        from: Date,
        to: Date,
        minimumVotes: Int,
        monetizationTypes: String? = nil
    ) async throws -> TMDBMovieListResponse {
        var extra = [
            "region": region,
            "with_release_type": releaseTypes,
            "release_date.gte": TMDBConfig.day(from),
            "release_date.lte": TMDBConfig.day(to),
            "vote_count.gte": String(minimumVotes),
            "sort_by": "popularity.desc",
            "include_adult": "false"
        ]
        if let monetizationTypes {
            extra["watch_region"] = region
            extra["with_watch_monetization_types"] = monetizationTypes
        }
        return try await get(["discover", "movie"], extra: extra)
    }

    /// External ids for a recommendation, used to bridge a TMDB id back to an IMDB id for navigation
    /// into the addon-backed detail screen (called only when a "More Like This" item is selected).
    func externalIDs(mediaType: String, id: Int) async throws -> TMDBExternalIDs {
        try await get([mediaType, String(id), "external_ids"])
    }

    /// Movies or series matching discover `parameters`.
    func discover(mediaType: String, parameters: [String: String]) async throws -> TMDBDiscoverResponse {
        try await get(["discover", mediaType], extra: parameters)
    }

    /// A title's logos and external ids, and nothing else.
    func titleSummary(mediaType: String, id: Int) async throws -> TMDBTitleSummary {
        try await get([mediaType, String(id)], extra: [
            "append_to_response": "images,external_ids",
            "include_image_language": "en,null"
        ])
    }

    func network(id: Int) async throws -> TMDBNetworkDetail {
        try await get(["network", String(id)])
    }

    // MARK: - Plumbing

    private func get<T: Decodable>(_ segments: [String], extra: [String: String] = [:]) async throws -> T {
        guard TMDBConfig.isConfigured else { throw TMDBClientError.notConfigured }

        var components = URLComponents(
            url: TMDBConfig.apiBaseURL.appending(path: segments.joined(separator: "/")),
            resolvingAgainstBaseURL: false
        )
        var query = [
            URLQueryItem(name: "api_key", value: TMDBConfig.apiKey),
            URLQueryItem(name: "language", value: TMDBConfig.language)
        ]
        query.append(contentsOf: extra.map { URLQueryItem(name: $0.key, value: $0.value) })
        components?.queryItems = query

        guard let url = components?.url else { throw TMDBClientError.invalidURL }
        return try await perform(url)
    }

    private func perform<T: Decodable>(_ url: URL) async throws -> T {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                throw TMDBClientError.http(status: -1)
            }
            guard (200..<300).contains(http.statusCode) else {
                throw TMDBClientError.http(status: http.statusCode)
            }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw TMDBClientError.decoding(error)
            }
        } catch let error as TMDBClientError {
            throw error
        } catch {
            throw TMDBClientError.transport(error)
        }
    }
}
