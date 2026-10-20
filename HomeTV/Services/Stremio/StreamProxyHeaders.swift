import Foundation

/// Stremio's `behaviorHints.proxyHeaders`: headers the stream's host requires. Only `request` is sent;
/// `response` is for proxies, which the in-app player doesn't use.
struct StreamProxyHeaders: Codable, Hashable, Sendable {
    var request: [String: String]?
    var response: [String: String]?
}
