import Foundation

/// Launches one movie or episode in the chosen player: the resume position, the season hand-off, the
/// Infuse filename, and the return registration. Shared by the stream picker and Continue Watching's
/// direct resume, so both launch exactly the same way.
@MainActor
final class PlaybackSession {
    let type: String
    let contentID: String
    /// The label the launching screen passed, such as `The Gentlemen — S1·E1`.
    let title: String
    /// The title's logo, for the in-app player's loading screen.
    let logoURL: URL?

    /// Resolves the rest of the season in the background. See `prepare`.
    private let queuePrefetcher = SeasonQueuePrefetcher()
    /// The show's numbered episodes, in play order, once its meta has loaded.
    private var seasonEpisodes: [SeasonQueueBuilder.Episode] = []
    /// The show's own name. `title` is the episode label, which would read as
    /// "The Gentlemen — S1·E1 S01E01.mkv" in the player.
    private var seasonShowName: String?
    /// The episode's own title from the show's meta, for the in-app player.
    private var episodeTitle: String?
    /// Runtime from the title's meta, for turning a reported position into a resume fraction.
    private var runtimeSeconds: Int?
    /// Release year from the title's meta, for a movie's `Name (Year).mkv` filename.
    private var releaseYear: Int?
    /// Set once the meta lookup has finished, found or not, so `launch` doesn't go without a runtime.
    private var isMetaResolved = false

    init(type: String, contentID: String, title: String, logoURL: String? = nil) {
        self.type = type
        self.contentID = contentID
        self.title = title
        self.logoURL = logoURL.flatMap(URL.init(string:))
    }

    /// Stops the season prefetch. Its work is unstructured, so closing the caller has to stop it explicitly.
    func cancel() {
        queuePrefetcher.cancel()
    }

    // MARK: - Launch

    /// Hands `stream` to the default player and remembers it as the title's choice.
    func launch(_ stream: Stream, addonID: String) async throws {
        let player = PlayerPreference.shared.defaultPlayer
        // Let the episodes ahead finish resolving, or the queue is only as long as whatever landed
        // while the user read the stream list. Bounded, and usually already satisfied.
        let expiry = ContinuousClock.now + SeasonQueuePrefetcher.coverageDeadline
        // The resume position needs the runtime, and the queue needs the episode list.
        while !isMetaResolved, ContinuousClock.now < expiry, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
        }
        await queuePrefetcher.awaitResolution(
            of: forwardEpisodeIDs,
            within: expiry - ContinuousClock.now
        )
        let queue = seasonQueue(for: stream, addonID: addonID, player: player)
        queuePrefetcher.cancel()
        // The caller gave up during the wait, e.g. the user left Watch Now: never open the player late.
        try Task.checkCancellation()
        // Every launch is registered, queue or not: the player's callback is how a movie or a single
        // episode gets its resume point too, not only a season hand-off.
        // Only Infuse's URL carries our callback: state left for any other player is never cleared, and
        // a late callback would then land on the wrong title.
        let token = PlaybackReturnCoordinator.makeToken()
        // The same key the Resume label reads, so the button and the launch agree.
        let startPosition = PlayerLauncher.resumePosition(
            fraction: UserLibrary.progress(forKey: contentID),
            runtimeSeconds: runtimeSeconds
        )
        let showID = Self.showID(fromEpisodeID: contentID)
        if player == .builtIn {
            try playInApp(stream, startPosition: startPosition)
            remember(stream, addonID: addonID, showID: showID)
            return
        }
        PlaybackReturnCoordinator.shared.willLaunch(
            player == .infuse
                ? .init(
                    token: token,
                    type: type,
                    contentID: contentID,
                    showID: showID,
                    runtimeSeconds: runtimeSeconds,
                    queue: queue
                )
                : nil
        )
        do {
            if let queue {
                try await PlayerLauncher.play(
                    queue: queue,
                    using: player,
                    title: title,
                    startPosition: startPosition,
                    token: token
                )
            } else {
                try await PlayerLauncher.play(
                    stream,
                    using: player,
                    title: title,
                    filename: launchFilename(for: stream),
                    startPosition: startPosition,
                    token: token
                )
            }
        } catch {
            PlaybackReturnCoordinator.shared.willLaunch(nil)
            throw error
        }
        remember(stream, addonID: addonID, showID: showID)
    }

    private func remember(_ stream: Stream, addonID: String, showID: String) {
        StreamChoiceStore.shared.record(
            StreamChoice(stream: stream, addonID: addonID, contentID: contentID),
            forTitle: showID
        )
    }

    /// Opens the stream in HomeTV's own player. Only HTTP streams play in-app; magnets need an external app.
    private func playInApp(_ stream: Stream, startPosition: Int?) throws {
        guard let url = stream.playableURL else { throw PlayerLaunchError.noPlayableURL }
        guard url.scheme == "http" || url.scheme == "https" else { throw PlayerLaunchError.unsupportedInApp }
        var request = PlayerRequest(
            url: url,
            title: title,
            logoURL: logoURL,
            headers: stream.behaviorHints?.proxyHeaders?.request ?? [:],
            startTime: TimeInterval(startPosition ?? 0)
        )
        // `title` is the picker's episode label; split it into the show name and the episode line.
        if type == "series", let showName = seasonShowName,
           let (season, episode) = PlaybackReturnCoordinator.episodeNumbers(in: contentID) {
            request.title = showName
            request.episodeLabel = PlayerEpisodeLabel.text(season: season, episode: episode, title: episodeTitle)
        }
        PlayerPresenter.shared.present(request)
    }

    /// The episodes after the selected one, where the queue grows first and furthest.
    private var forwardEpisodeIDs: [String] {
        Self.prefetchEpisodeIDs(
            episodes: seasonEpisodes,
            selectedEpisodeID: contentID,
            forwardOnly: true
        )
    }

    /// The name Infuse identifies a single launch by: a movie, or an episode with no season queue.
    private func launchFilename(for stream: Stream) -> String? {
        guard let url = stream.playableURL else { return nil }
        guard type == "series" else {
            return PlayerFilename.movie(title: title, year: releaseYear, url: url)
        }
        guard let (season, episode) = PlaybackReturnCoordinator.episodeNumbers(in: contentID) else { return nil }
        let episodeTitle = seasonEpisodes.first { $0.id == contentID }?.title
        return PlayerFilename.episode(
            showName: seasonShowName ?? title,
            season: season,
            episode: episode,
            episodeTitle: episodeTitle,
            url: url
        )
    }

    /// The season hand-off for the chosen stream, or nil to launch the single episode exactly as before.
    private func seasonQueue(for stream: Stream, addonID: String, player: ExternalPlayer) -> PlaybackQueue? {
        guard player == .infuse, type == "series", !seasonEpisodes.isEmpty else { return nil }
        return SeasonQueueBuilder.queue(
            showID: Self.showID(fromEpisodeID: contentID),
            showName: seasonShowName ?? title,
            runtimeSeconds: runtimeSeconds,
            episodes: seasonEpisodes,
            selectedEpisodeID: contentID,
            selectedStream: stream,
            addonID: addonID,
            candidates: queuePrefetcher.candidates
        )
    }

    // MARK: - Season prefetch

    /// A series episode id is `<show id>:<season>:<episode>`; the show's meta lives under the bare id.
    nonisolated static func showID(fromEpisodeID id: String) -> String {
        String(id.split(separator: ":").first ?? "")
    }

    /// Seconds from an add-on's runtime string: `58 min`, `1h 2min`, or a bare number of minutes.
    nonisolated static func runtimeSeconds(from raw: String?) -> Int? {
        guard let raw else { return nil }
        let hours = raw.firstMatch(of: /(\d+)\s*h/.ignoresCase()).flatMap { Int($0.1) } ?? 0
        let minutes = raw.firstMatch(of: /(\d+)\s*m/.ignoresCase()).flatMap { Int($0.1) }
            ?? (hours == 0 ? raw.firstMatch(of: /(\d+)/).flatMap { Int($0.1) } : nil)
            ?? 0
        let total = hours * 3600 + minutes * 60
        return total > 0 ? total : nil
    }

    /// The episodes worth resolving: only `maxEntries` either side of the selection can reach the queue.
    nonisolated static func prefetchEpisodeIDs(
        episodes: [SeasonQueueBuilder.Episode],
        selectedEpisodeID: String,
        limit: Int = SeasonQueueBuilder.maxEntries,
        forwardOnly: Bool = false
    ) -> [String] {
        guard let index = episodes.firstIndex(where: { $0.id == selectedEpisodeID }) else { return [] }
        let forward = episodes[episodes.index(after: index)...].prefix(limit - 1).map(\.id)
        guard !forwardOnly else { return Array(forward) }
        let backward = episodes[..<index].suffix(limit - 1).reversed().map(\.id)
        // Forward first, each direction outward: the queue grows contiguously from the selection.
        return Array(forward) + backward
    }

    /// Loads the title's meta for the runtime, and for a series its episode list, then starts resolving
    /// the neighbouring episodes' streams. Runs alongside the stream lookup; `launch` waits for it.
    func prepare() async {
        isMetaResolved = false
        defer { isMetaResolved = true }
        guard ProcessInfo.processInfo.environment["MOCK_STREAMS"] != "1" else { return }
        // The runtime feeds the resume position, which only Infuse and the in-app player take. The rest
        // exists to build an Infuse hand-off.
        let player = PlayerPreference.shared.defaultPlayer
        guard player == .infuse || player == .builtIn else { return }
        let showID = Self.showID(fromEpisodeID: contentID)
        guard !showID.isEmpty else { return }
        let registry = AddonRegistry.shared

        // Meta is cached in `StremioClient` for five minutes, so coming from the detail screen this is
        // almost always a warm read rather than a fetch.
        // Each add-on fills what the previous ones lacked. A series keeps looking until one returns an
        // episode list, which is what the queue is built from.
        var videos: [Video]?
        for addon in registry.enabledAddons {
            guard !Task.isCancelled else { return }
            guard let response = try? await StremioClient.shared.meta(
                baseURL: addon.baseURL, type: type, id: showID
            ) else { continue }
            let meta = response.meta
            runtimeSeconds = runtimeSeconds ?? Self.runtimeSeconds(from: meta.runtime)
            releaseYear = releaseYear ?? PlayerFilename.year(fromReleaseInfo: meta.releaseInfo)
            // The show's own name, for the filenames Infuse matches on.
            seasonShowName = seasonShowName ?? meta.name
            if let found = meta.videos, !found.isEmpty { videos = found }
            if type == "series" {
                if videos?.isEmpty == false { break }
            } else if runtimeSeconds != nil, releaseYear != nil {
                break
            }
        }

        episodeTitle = videos?.first { $0.id == contentID }?.episodeTitle

        // Cancelled callers have already stopped the prefetcher; don't start it again behind them.
        guard player == .infuse, type == "series", showID != contentID, !Task.isCancelled else { return }
        let streamAddons = registry.enabledAddons.filter { addon in
            (addon.manifest.resources ?? []).contains { $0.name == "stream" }
        }
        guard !streamAddons.isEmpty, let videos, !videos.isEmpty else { return }
        let episodes = SeasonQueueBuilder.orderedEpisodes(from: videos)
        seasonEpisodes = episodes
        queuePrefetcher.start(
            type: type,
            episodeIDs: Self.prefetchEpisodeIDs(episodes: episodes, selectedEpisodeID: contentID),
            addons: streamAddons
        )
    }
}
