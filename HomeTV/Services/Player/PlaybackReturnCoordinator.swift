import Foundation

/// Remembers what HomeTV last handed to an external player, and reconciles the library when the player
/// hands control back.
///
/// The player's `x-success` callback fires once, when the playlist ends or the player is closed:
///
///     hometv://playback-done-<token>?lastPlayedUrl=<url>&position=<seconds>
///
/// It cannot distinguish a finished season from a quit, so only the episodes the playlist provably got
/// past are marked watched; the one it came back on gets a resume point instead.
@MainActor
final class PlaybackReturnCoordinator {
    static let shared = PlaybackReturnCoordinator()

    /// What is playing elsewhere right now. Belongs to the launch, not to a persisted global.
    struct Launch {
        /// Echoed back by the player. `hometv://` is public, so without it any app could discard a
        /// pending reconciliation or forge a completion.
        let token: String
        let type: String
        /// Stremio content id of the item actually launched: `tt0903747` or `tt0903747:1:4`.
        let contentID: String
        /// The show (or the movie itself) — the id Continue Watching cards are keyed by.
        let showID: String
        /// Episode runtime, when known, so a position in seconds can become a fraction.
        let runtimeSeconds: Int?
        /// The season hand-off, when this launch was one. Movies and single episodes have no queue.
        let queue: PlaybackQueue?
    }

    private(set) var activeLaunch: Launch?

    private init() {}

    func willLaunch(_ launch: Launch?) {
        activeLaunch = launch
    }

    /// A fresh token for a launch: 32 hex characters, 128 bits.
    static func makeToken() -> String {
        String((0..<32).compactMap { _ in "0123456789abcdef".randomElement() })
    }

    /// Handles `hometv://playback-done` and `hometv://playback-error`. Returns true when the link was
    /// ours, so `HomeTVApp` knows not to hand it on to `DeepLinkRouter`.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard url.scheme == PlayerLauncher.callbackScheme else { return false }
        guard let (host, token) = Self.split(host: url.host) else { return false }

        // Ours by scheme either way, but only this launch's token may change anything.
        guard let launch = activeLaunch, token == launch.token else { return true }

        if host == "playback-done" {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            reconcile(launch, with: items)
        }
        activeLaunch = nil
        return true
    }

    private func reconcile(_ launch: Launch, with items: [URLQueryItem]) {
        let position = value(named: Self.positionParameter, in: items).flatMap(Int.init)

        // Which item the player came back on: located by URL in a queue, otherwise the one we launched.
        var returned = launch.contentID
        var runtime = launch.runtimeSeconds
        if let queue = launch.queue,
           let raw = value(named: Self.lastPlayedURLParameter, in: items),
           let last = URL(string: raw),
           let index = queue.index(ofEntryMatching: last) {
            for entry in queue.entries.prefix(index) {
                UserLibrary.markEpisodeWatched(
                    showID: queue.showID,
                    season: entry.season,
                    episode: entry.episode
                )
            }
            returned = queue.entries[index].episodeID
            runtime = queue.entries[index].runtimeSeconds ?? runtime
        } else if launch.queue != nil {
            return      // a queue we could not place the return in — better to record nothing
        }

        guard let position, let runtime, runtime > 0 else { return }
        let fraction = Double(position) / Double(runtime)
        UserLibrary.recordProgress(fraction, id: returned)
        // Continue Watching cards are keyed by the show, so the resume point is recorded there too.
        if returned != launch.showID, !launch.showID.isEmpty {
            UserLibrary.recordProgress(fraction, id: launch.showID)
        }
    }

    /// Parameter names Infuse uses; its docs describe the behaviour but not the spelling. Compared
    /// case-insensitively so a change does not silently stop this.
    static let lastPlayedURLParameter = "lastPlayedUrl"
    static let positionParameter = "position"

    static let doneHost = "playback-done"
    static let errorHost = "playback-error"

    /// Splits `playback-done-<token>` into its two parts, or nil when the host is not one of ours.
    /// A bare host with no token yields an empty token, which never equals a launch's.
    static func split(host: String?) -> (host: String, token: String)? {
        guard let host else { return nil }
        for known in [doneHost, errorHost] {
            if host == known { return (known, "") }
            if host.hasPrefix("\(known)-") { return (known, String(host.dropFirst(known.count + 1))) }
        }
        return nil
    }

    private func value(named name: String, in items: [URLQueryItem]) -> String? {
        items.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}
