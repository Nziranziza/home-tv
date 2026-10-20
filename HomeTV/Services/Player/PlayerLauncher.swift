import Foundation
import UIKit

enum PlayerLaunchError: Error, LocalizedError {
    case noPlayableURL
    case unsupportedInApp
    case playerUnavailable(ExternalPlayer)
    case failedToOpen

    var errorDescription: String? {
        switch self {
        case .noPlayableURL: "This stream has no playable URL."
        case .unsupportedInApp: "This stream can't play in HomeTV. Choose a direct stream, or switch players in Settings."
        case .playerUnavailable(let p): "\(p.displayName) is not installed on this Apple TV."
        case .failedToOpen: "Failed to hand off to the external player."
        }
    }
}

@MainActor
enum PlayerLauncher {
    static let callbackScheme = "hometv"

    static func play(
        _ stream: Stream,
        using player: ExternalPlayer,
        title: String? = nil,
        filename: String? = nil,
        startPosition: Int? = nil,
        token: String? = nil
    ) async throws {
        guard let url = stream.playableURL else { throw PlayerLaunchError.noPlayableURL }
        try await open(
            mediaURL: url,
            using: player,
            title: title ?? stream.displayTitle,
            filename: filename,
            startPosition: startPosition,
            token: token
        )
    }

    /// Hands an ordered season to the player. Infuse's `play` action takes repeated
    /// `url`/`position`/`filename` sets and plays them in order; every other scheme takes one URL, so
    /// those get the selected episode alone. `startPosition` applies to the selected episode only.
    static func play(
        queue: PlaybackQueue,
        using player: ExternalPlayer,
        title: String? = nil,
        startPosition: Int? = nil,
        token: String? = nil
    ) async throws {
        guard let first = queue.first else { throw PlayerLaunchError.noPlayableURL }
        if player == .infuse, queue.entries.count > 1,
           let target = infusePlaylistURL(queue: queue, startPosition: startPosition, token: token) {
            // Refused: fall through to the single-URL launch rather than cost the chosen episode.
            if await tryOpen(target) { return }
        }
        try await open(
            mediaURL: first.url,
            using: player,
            title: title,
            filename: first.filename,
            startPosition: startPosition,
            token: token
        )
    }

    /// Seconds to resume at, or nil to start from the beginning. Only a fraction inside
    /// `LocalLibrary.resumeRange` resumes, and an unknown runtime never guesses.
    static func resumePosition(fraction: Double?, runtimeSeconds: Int?) -> Int? {
        guard let fraction, LocalLibrary.resumeRange.contains(fraction),
              let runtimeSeconds, runtimeSeconds > 0 else { return nil }
        let seconds = Int(fraction * Double(runtimeSeconds))
        return seconds > 0 ? seconds : nil
    }

    static func open(
        mediaURL: URL,
        using player: ExternalPlayer,
        title: String? = nil,
        filename: String? = nil,
        startPosition: Int? = nil,
        token: String? = nil
    ) async throws {
        let target = launchURL(
            for: mediaURL,
            player: player,
            title: title,
            filename: filename,
            startPosition: startPosition,
            token: token
        )
        guard let target else { throw PlayerLaunchError.playerUnavailable(player) }
        try await openTarget(target, player: player)
    }

    private static func openTarget(_ target: URL, player: ExternalPlayer) async throws {
        guard UIApplication.shared.canOpenURL(target) else {
            throw PlayerLaunchError.playerUnavailable(player)
        }
        let ok = await UIApplication.shared.open(target, options: [:])
        if !ok { throw PlayerLaunchError.failedToOpen }
    }

    /// `openTarget` without the throwing, for attempts that have a fallback.
    private static func tryOpen(_ target: URL) async -> Bool {
        guard UIApplication.shared.canOpenURL(target) else { return false }
        return await UIApplication.shared.open(target, options: [:])
    }

    static func launchURL(
        for mediaURL: URL,
        player: ExternalPlayer,
        title: String?,
        filename: String? = nil,
        startPosition: Int? = nil,
        token: String? = nil
    ) -> URL? {
        switch player {
        case .infuse:
            return infuseURL(
                media: mediaURL,
                title: title,
                filename: filename,
                startPosition: startPosition,
                token: token
            )
        // Neither VLC's `stream` action nor a bare media URL takes a start time.
        case .vlc:
            return vlcURL(media: mediaURL)
        case .system:
            return mediaURL
        // Plays in-app through `PlayerPresenter`; there's no app to hand a URL to.
        case .builtIn:
            return nil
        }
    }

    /// A single-item `play` call. `filename` is what Infuse identifies the title by — its scheme has no
    /// `name` parameter. `title` is kept for the players that do take one. `startPosition` is in seconds.
    static func infuseURL(
        media: URL,
        title: String?,
        filename: String? = nil,
        startPosition: Int? = nil,
        token: String? = nil
    ) -> URL? {
        var pairs = ["url=\(strictlyEncoded(media.absoluteString))"]
        if let startPosition, startPosition > 0 {
            pairs.append("position=\(startPosition)")
        }
        if let filename, !filename.isEmpty {
            pairs.append("filename=\(strictlyEncoded(filename))")
        } else if let title, !title.isEmpty {
            pairs.append("filename=\(strictlyEncoded(title))")
        }
        pairs.append("x-success=\(callbackValue(callbackURL("playback-done", token: token)))")
        pairs.append("x-error=\(callbackValue(callbackURL("playback-error", token: token)))")

        var components = URLComponents()
        components.scheme = "infuse"
        components.host = "x-callback-url"
        components.path = "/play"
        components.percentEncodedQuery = pairs.joined(separator: "&")
        return components.url
    }

    /// A multi-item `play` call. Infuse pairs the repeated keys positionally, so every item carries
    /// every key — omitting one would shift the rest of the list. The query is encoded by hand because
    /// `queryItems` leaves `&`, `=`, `+` and `?` raw inside a value, which corrupts the whole call.
    /// `startPosition` resumes the selected (first) entry; the rest start at 0.
    static func infusePlaylistURL(queue: PlaybackQueue, startPosition: Int? = nil, token: String? = nil) -> URL? {
        var pairs: [String] = []
        for (index, entry) in queue.entries.enumerated() {
            let position = index == 0 ? max(startPosition ?? 0, 0) : 0
            pairs.append("url=\(strictlyEncoded(entry.url.absoluteString))")
            pairs.append("position=\(position)")
            pairs.append("filename=\(strictlyEncoded(entry.filename))")
        }
        // Called once, when the playlist ends or the player closes — not per item. Routed by
        // `PlaybackReturnCoordinator`, which uses the returned URL to reconcile watch state.
        pairs.append("x-success=\(callbackValue(callbackURL("playback-done", token: token)))")
        pairs.append("x-error=\(callbackValue(callbackURL("playback-error", token: token)))")

        var components = URLComponents()
        components.scheme = "infuse"
        components.host = "x-callback-url"
        components.path = "/play"
        components.percentEncodedQuery = pairs.joined(separator: "&")
        return components.url
    }

    /// Percent-encodes everything outside the RFC 3986 unreserved set, so a value can never be mistaken
    /// for query structure.
    private static func strictlyEncoded(_ value: String) -> String {
        var unreserved = CharacterSet.alphanumerics
        unreserved.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    /// Callback URLs keep their readable spelling: they contain nothing that could split the query, and
    /// encoding them would rely on Infuse decoding each value before opening it.
    /// `hometv://playback-done-<token>`. The token rides in the host, not the query, because the player
    /// appends its own parameters to this URL and nothing appends to a host.
    private static func callbackURL(_ host: String, token: String?) -> String {
        guard let token, !token.isEmpty else { return "\(callbackScheme)://\(host)" }
        return "\(callbackScheme)://\(host)-\(token)"
    }

    private static func callbackValue(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
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
