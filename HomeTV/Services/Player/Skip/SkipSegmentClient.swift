import Foundation

/// Reads community intro, recap and credits timestamps from TheIntroDB and IntroDB.app. Both are
/// anonymous; a failure or a missing entry yields no segments.
actor SkipSegmentClient {
    static let shared = SkipSegmentClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    /// Per title for the session. A lookup that failed is dropped, so the next play retries it.
    private var cache: [SkipSegmentQuery: Task<[SkipSegmentSource], Never>] = [:]

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 10
            config.timeoutIntervalForResource = 15
            config.waitsForConnectivity = false
            self.session = URLSession(configuration: config)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    /// The databases' segments in priority order: TheIntroDB, then IntroDB.app.
    func sources(for query: SkipSegmentQuery) async -> [SkipSegmentSource] {
        if let task = cache[query] { return await task.value }
        let task = Task { await fetch(query) }
        cache[query] = task
        return await task.value
    }

    private func fetch(_ query: SkipSegmentQuery) async -> [SkipSegmentSource] {
        async let theIntroDB = load(TheIntroDBResponse.self, from: Self.theIntroDBURL(for: query))
        async let introDBApp = load(IntroDBAppResponse.self, from: Self.introDBAppURL(for: query))
        let results = await (theIntroDB, introDBApp)
        if results.0 == nil || results.1 == nil { cache[query] = nil }
        return [results.0??.source, results.1??.source].compactMap { $0 }
    }

    /// Nil when the request failed, including a response that didn't decode; `.some(nil)` when the title
    /// isn't in the database.
    private func load<Response: Decodable>(_ type: Response.Type, from url: URL?) async -> Response?? {
        guard let url else { return .some(nil) }
        do {
            let (data, response) = try await session.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 { return .some(nil) }
            guard (200..<300).contains(status) else { return nil }
            return try decoder.decode(Response.self, from: data)
        } catch {
            return nil
        }
    }

    static func theIntroDBURL(for query: SkipSegmentQuery) -> URL? {
        url("https://api.theintrodb.org/v4/media", query: query, movieItems: [])
    }

    static func introDBAppURL(for query: SkipSegmentQuery) -> URL? {
        url("https://api.introdb.app/segments", query: query, movieItems: [URLQueryItem(name: "is_movie", value: "true")])
    }

    private static func url(_ base: String, query: SkipSegmentQuery, movieItems: [URLQueryItem]) -> URL? {
        var components = URLComponents(string: base)
        var items = [URLQueryItem(name: "imdb_id", value: query.imdbID)]
        if let season = query.season, let episode = query.episode {
            items += [URLQueryItem(name: "season", value: String(season)), URLQueryItem(name: "episode", value: String(episode))]
        } else {
            items += movieItems
        }
        components?.queryItems = items
        return components?.url
    }
}
