import Foundation

extension StremioClient {
    func subtitles(baseURL: URL, query: SubtitleAddonQuery) async throws -> SubtitlesResponse {
        guard let url = Self.subtitlesURL(baseURL: baseURL, query: query) else {
            throw StremioClientError.invalidBaseURL
        }
        return try await get(url: url, as: SubtitlesResponse.self)
    }

    /// `{base}/subtitles/{type}/{id}/{extra}.json`, each part encoded like `encodeURIComponent`. The route
    /// goes on the base's path, so a configured add-on's query stays a query.
    nonisolated static func subtitlesURL(baseURL: URL, query: SubtitleAddonQuery) -> URL? {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
        let encode = { (value: String) in value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value }
        var route = "subtitles/\(encode(query.type))/\(encode(query.id))"
        let extra = query.extra.map { "\($0.name)=\(encode($0.value))" }.joined(separator: "&")
        if !extra.isEmpty { route += "/\(extra)" }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        var path = components.percentEncodedPath
        if path.hasSuffix("/manifest.json") { path.removeLast("/manifest.json".count) }
        while path.hasSuffix("/") { path.removeLast() }
        components.percentEncodedPath = "\(path)/\(route).json"
        return components.url
    }
}
