import Foundation

enum StremioClientError: Error, LocalizedError {
    case invalidBaseURL
    case invalidResponse(status: Int)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL: "Invalid addon URL"
        case .invalidResponse(let status): "Addon returned HTTP \(status)"
        case .decoding(let error): "Failed to decode addon response: \(error.localizedDescription)"
        case .transport(let error): "Network error: \(error.localizedDescription)"
        }
    }
}

actor StremioClient {
    static let shared = StremioClient()

    private let session: URLSession
    private let decoder: JSONDecoder

    /// Short-lived catalog cache so the same catalog (e.g. the first row, also used for the hero)
    /// isn't fetched twice per screen. Coalescing collapses simultaneous identical requests.
    private struct CatalogCacheEntry {
        let date: Date
        let value: CatalogResponse
    }
    private var catalogCache: [URL: CatalogCacheEntry] = [:]
    private var catalogInFlight: [URL: Task<CatalogResponse, Error>] = [:]
    private let catalogTTL: TimeInterval = 300

    /// Same short-lived cache + coalescing for `meta`, so re-entering a detail screen (or its `.task(id:)`
    /// re-firing) doesn't re-fetch and re-decode the full title — which for a long series is a large
    /// episode-list payload. Mirrors the catalog cache above.
    private struct MetaCacheEntry {
        let date: Date
        let value: MetaResponse
    }
    private var metaCache: [URL: MetaCacheEntry] = [:]
    private var metaInFlight: [URL: Task<MetaResponse, Error>] = [:]
    private let metaTTL: TimeInterval = 300

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 5
            config.timeoutIntervalForResource = 10
            config.waitsForConnectivity = false
            self.session = URLSession(configuration: config)
        }
        self.decoder = JSONDecoder()
    }

    func manifest(manifestURL: URL) async throws -> StremioManifest {
        try await get(url: manifestURL, as: StremioManifest.self)
    }

    func catalog(baseURL: URL, type: String, id: String, extra: [String: String] = [:]) async throws -> CatalogResponse {
        let url = endpoint(base: baseURL, segments: ["catalog", type, id], extra: extra)

        if let entry = catalogCache[url], Date().timeIntervalSince(entry.date) < catalogTTL {
            return entry.value
        }
        if let existing = catalogInFlight[url] {
            return try await existing.value
        }

        let task = Task { try await get(url: url, as: CatalogResponse.self) }
        catalogInFlight[url] = task
        do {
            let value = try await task.value
            catalogInFlight[url] = nil
            catalogCache[url] = CatalogCacheEntry(date: Date(), value: value)
            return value
        } catch {
            catalogInFlight[url] = nil
            throw error
        }
    }

    func meta(baseURL: URL, type: String, id: String) async throws -> MetaResponse {
        let url = endpoint(base: baseURL, segments: ["meta", type, id])

        if let entry = metaCache[url], Date().timeIntervalSince(entry.date) < metaTTL {
            return entry.value
        }
        if let existing = metaInFlight[url] {
            return try await existing.value
        }

        let task = Task { try await get(url: url, as: MetaResponse.self) }
        metaInFlight[url] = task
        do {
            let value = try await task.value
            metaInFlight[url] = nil
            metaCache[url] = MetaCacheEntry(date: Date(), value: value)
            return value
        } catch {
            metaInFlight[url] = nil
            throw error
        }
    }

    func streams(baseURL: URL, type: String, id: String) async throws -> StreamResponse {
        let url = endpoint(base: baseURL, segments: ["stream", type, id])
        return try await get(url: url, as: StreamResponse.self)
    }

    /// Generic decoded GET against an addon endpoint. Exposed (internal) so the Trailerio extension can
    /// reuse the client's session/error handling for its non-standard `meta` response without
    /// duplicating networking.
    func fetch<T: Decodable & Sendable>(baseURL: URL, segments: [String], as type: T.Type) async throws -> T {
        try await get(url: endpoint(base: baseURL, segments: segments), as: type)
    }

    private func endpoint(base: URL, segments: [String], extra: [String: String] = [:]) -> URL {
        let trimmed = trimmedBase(base)
        var path = segments.joined(separator: "/")
        if !extra.isEmpty {
            let encoded = extra.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
            path += "/\(encoded)"
        }
        path += ".json"
        return trimmed.appendingPathComponent(path)
    }

    private func trimmedBase(_ url: URL) -> URL {
        let s = url.absoluteString
        if s.hasSuffix("/manifest.json") {
            return URL(string: String(s.dropLast("/manifest.json".count))) ?? url
        }
        if s.hasSuffix("/") {
            return URL(string: String(s.dropLast())) ?? url
        }
        return url
    }

    private func get<T: Decodable>(url: URL, as type: T.Type) async throws -> T {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                throw StremioClientError.invalidResponse(status: -1)
            }
            guard (200..<300).contains(http.statusCode) else {
                throw StremioClientError.invalidResponse(status: http.statusCode)
            }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw StremioClientError.decoding(error)
            }
        } catch let error as StremioClientError {
            throw error
        } catch {
            throw StremioClientError.transport(error)
        }
    }
}
