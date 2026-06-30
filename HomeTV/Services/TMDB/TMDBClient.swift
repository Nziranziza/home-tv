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

    /// Per-season episode metadata (runtime/stills/overviews) and the season poster.
    func season(tvID: Int, season: Int) async throws -> TMDBSeasonDetail {
        try await get(["tv", String(tvID), "season", String(season)])
    }

    /// Where the title can be watched (JustWatch data), grouped by country then availability type.
    func watchProviders(mediaType: String, id: Int) async throws -> TMDBWatchProviders {
        try await get([mediaType, String(id), "watch", "providers"])
    }

    /// External ids for a recommendation, used to bridge a TMDB id back to an IMDB id for navigation
    /// into the addon-backed detail screen (called only when a "More Like This" item is selected).
    func externalIDs(mediaType: String, id: Int) async throws -> TMDBExternalIDs {
        try await get([mediaType, String(id), "external_ids"])
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
