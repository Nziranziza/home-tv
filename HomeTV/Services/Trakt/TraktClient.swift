import Foundation

enum TraktClientError: Error, LocalizedError {
    case notConfigured
    case http(status: Int)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Trakt API keys are not configured."
        case .http(let status): "Trakt returned HTTP \(status)."
        case .decoding(let error): "Failed to decode Trakt response: \(error.localizedDescription)"
        case .transport(let error): "Network error: \(error.localizedDescription)"
        }
    }

    /// During device-code polling Trakt returns 400 while the user hasn't entered the code yet.
    var isAuthorizationPending: Bool {
        if case .http(let status) = self { return status == 400 }
        return false
    }
}

/// Thin async wrapper over the Trakt REST API, mirroring `StremioClient`'s actor + ephemeral-session
/// shape. It knows nothing about app state — it just signs requests with the standard Trakt headers
/// (+ optional bearer token), performs them, and decodes. All higher-level logic (token lifecycle,
/// caches, optimistic updates) lives in `TraktService`.
actor TraktClient {
    static let shared = TraktClient()

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

    // MARK: - OAuth (device flow)

    func deviceCode() async throws -> TraktDeviceCode {
        let body = try json(["client_id": TraktConfig.clientID])
        let data = try await perform(request("oauth/device/code", method: "POST", body: body))
        return try decode(data)
    }

    /// One poll of the device-token endpoint. Throws `.http(400)` (→ `isAuthorizationPending`) while
    /// the user hasn't authorized yet; throws other statuses (404 invalid / 409 used / 410 expired /
    /// 418 denied) for the caller to stop on.
    func deviceToken(deviceCode: String) async throws -> TraktTokens {
        let body = try json([
            "code": deviceCode,
            "client_id": TraktConfig.clientID,
            "client_secret": TraktConfig.clientSecret
        ])
        let data = try await perform(request("oauth/device/token", method: "POST", body: body))
        return try decode(data)
    }

    func refresh(refreshToken: String) async throws -> TraktTokens {
        let body = try json([
            "refresh_token": refreshToken,
            "client_id": TraktConfig.clientID,
            "client_secret": TraktConfig.clientSecret,
            "redirect_uri": TraktConfig.redirectURI,
            "grant_type": "refresh_token"
        ])
        let data = try await perform(request("oauth/token", method: "POST", body: body))
        return try decode(data)
    }

    // MARK: - Account

    func user(token: String) async throws -> TraktUser {
        let data = try await perform(request("users/me", token: token))
        return try decode(data)
    }

    // MARK: - Sync writes (response body ignored — success is the 2xx)

    func addToHistory(body: Data, token: String) async throws {
        _ = try await perform(request("sync/history", method: "POST", body: body, token: token))
    }

    func removeFromHistory(body: Data, token: String) async throws {
        _ = try await perform(request("sync/history/remove", method: "POST", body: body, token: token))
    }

    func addToWatchlist(body: Data, token: String) async throws {
        _ = try await perform(request("sync/watchlist", method: "POST", body: body, token: token))
    }

    func removeFromWatchlist(body: Data, token: String) async throws {
        _ = try await perform(request("sync/watchlist/remove", method: "POST", body: body, token: token))
    }

    // MARK: - Sync reads

    func watchedMovies(token: String) async throws -> [TraktWatchedMovie] {
        try decode(try await perform(request("sync/watched/movies", token: token)))
    }

    func watchedShows(token: String) async throws -> [TraktWatchedShow] {
        try decode(try await perform(request("sync/watched/shows", token: token)))
    }

    func watchlistMovies(token: String) async throws -> [TraktWatchlistMovie] {
        try decode(try await perform(request("sync/watchlist/movies", token: token)))
    }

    func watchlistShows(token: String) async throws -> [TraktWatchlistShow] {
        try decode(try await perform(request("sync/watchlist/shows", token: token)))
    }

    func playbackMovies(token: String) async throws -> [TraktPlaybackItem] {
        try decode(try await perform(request("sync/playback/movies", token: token)))
    }

    func playbackEpisodes(token: String) async throws -> [TraktPlaybackItem] {
        try decode(try await perform(request("sync/playback/episodes", token: token)))
    }

    // MARK: - Plumbing

    private func request(_ path: String, method: String = "GET", body: Data? = nil, token: String? = nil) -> URLRequest {
        // Concatenate rather than appendingPathComponent so multi-segment paths stay literal.
        let url = URL(string: TraktConfig.apiBaseURL.absoluteString + "/" + path)!
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("2", forHTTPHeaderField: "trakt-api-version")
        req.setValue(TraktConfig.clientID, forHTTPHeaderField: "trakt-api-key")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = body
        return req
    }

    @discardableResult
    private func perform(_ req: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw TraktClientError.http(status: -1)
            }
            guard (200..<300).contains(http.statusCode) else {
                throw TraktClientError.http(status: http.statusCode)
            }
            return data
        } catch let error as TraktClientError {
            throw error
        } catch {
            throw TraktClientError.transport(error)
        }
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw TraktClientError.decoding(error)
        }
    }

    private func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }
}
