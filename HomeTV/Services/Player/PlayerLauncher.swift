import Foundation
import UIKit

enum PlayerLaunchError: Error, LocalizedError {
    case noPlayableURL
    case playerUnavailable(ExternalPlayer)
    case failedToOpen

    var errorDescription: String? {
        switch self {
        case .noPlayableURL: "This stream has no playable URL."
        case .playerUnavailable(let p): "\(p.displayName) is not installed on this Apple TV."
        case .failedToOpen: "Failed to hand off to the external player."
        }
    }
}

@MainActor
enum PlayerLauncher {
    static let callbackScheme = "hometv"

    static func play(_ stream: Stream, using player: ExternalPlayer, title: String? = nil) async throws {
        guard let url = stream.playableURL else { throw PlayerLaunchError.noPlayableURL }
        try await open(mediaURL: url, using: player, title: title ?? stream.displayTitle)
    }

    static func open(mediaURL: URL, using player: ExternalPlayer, title: String? = nil) async throws {
        let target = launchURL(for: mediaURL, player: player, title: title)
        guard let target else { throw PlayerLaunchError.playerUnavailable(player) }
        guard UIApplication.shared.canOpenURL(target) else {
            throw PlayerLaunchError.playerUnavailable(player)
        }
        let ok = await UIApplication.shared.open(target, options: [:])
        if !ok { throw PlayerLaunchError.failedToOpen }
    }

    static func launchURL(for mediaURL: URL, player: ExternalPlayer, title: String?) -> URL? {
        switch player {
        case .infuse:
            return infuseURL(media: mediaURL, title: title)
        case .vlc:
            return vlcURL(media: mediaURL)
        case .system:
            return mediaURL
        }
    }

    private static func infuseURL(media: URL, title: String?) -> URL? {
        var components = URLComponents()
        components.scheme = "infuse"
        components.host = "x-callback-url"
        components.path = "/play"
        var items: [URLQueryItem] = [URLQueryItem(name: "url", value: media.absoluteString)]
        if let title { items.append(URLQueryItem(name: "name", value: title)) }
        items.append(URLQueryItem(name: "x-success", value: "\(callbackScheme)://playback-done"))
        items.append(URLQueryItem(name: "x-error", value: "\(callbackScheme)://playback-error"))
        components.queryItems = items
        return components.url
    }

    private static func vlcURL(media: URL) -> URL? {
        var components = URLComponents()
        components.scheme = "vlc-x-callback"
        components.host = "x-callback-url"
        components.path = "/stream"
        components.queryItems = [URLQueryItem(name: "url", value: media.absoluteString)]
        return components.url
    }
}
