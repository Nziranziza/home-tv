import Foundation

/// Where a stream's redirects end. FFmpeg follows a debrid link's redirect chain again on every range
/// request, at a second or more each, so the FFmpeg route opens the final URL instead.
enum StreamRedirect {
    static func finalURL(of url: URL, headers: [String: String]) async -> URL {
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "HEAD"
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let final = http.url else { return url }
        return final
    }
}
