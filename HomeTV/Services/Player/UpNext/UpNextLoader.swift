import Foundation

/// Finds the episode after the one playing and the stream that continues its release.
@MainActor
enum UpNextLoader {
    /// Nil when the play has no continuation, the show has no next episode, or its add-on has no stream
    /// from the same release. Crosses into the next season like the season queue does. Throws when a
    /// request failed, so the caller can try again.
    static func load(after request: PlayerRequest) async throws -> UpNextEpisode? {
        guard request.type == "series", let item = request.item, let continuation = request.continuation else {
            return nil
        }
        let addons = AddonRegistry.shared.enabledAddons

        // Meta is cached by `StremioClient`, so this is usually the read the launch already made.
        var videos: [Video] = []
        var runtimeSeconds: Int?
        var showName: String?
        var metaError: (any Error)?
        for addon in addons {
            guard !Task.isCancelled else { return nil }
            let meta: Meta
            do {
                meta = try await StremioClient.shared.meta(baseURL: addon.baseURL, type: request.type, id: item.showID).meta
            } catch {
                metaError = error
                continue
            }
            runtimeSeconds = runtimeSeconds ?? PlaybackSession.runtimeSeconds(from: meta.runtime)
            showName = showName ?? meta.name
            if let found = meta.videos, !found.isEmpty {
                videos = found
                break
            }
        }

        // No episode list because every add-on failed is worth another try; one that has none is not.
        if videos.isEmpty, let metaError { throw metaError }
        guard let next = nextEpisode(after: item.contentID, in: videos),
              let season = next.season, let episode = next.episode,
              let addon = addons.first(where: { $0.id == continuation.addonID })
        else { return nil }
        let streams = try await StremioClient.shared.streams(baseURL: addon.baseURL, type: request.type, id: next.id).streams
        guard !Task.isCancelled else { return nil }

        let candidates = streams.map { SeasonQueueBuilder.Candidate(stream: $0, addonID: addon.id) }
        guard let stream = SeasonQueueBuilder.sameRelease(
            as: continuation.release, addonID: addon.id, among: candidates
        ) else { return nil }

        let startTime = PlayerLauncher.resumePosition(
            savedSeconds: UserLibrary.resumeSeconds(forKey: next.id),
            fraction: UserLibrary.progress(forKey: next.id),
            runtimeSeconds: runtimeSeconds
        )
        let label = PlayerEpisodeLabel.text(season: season, episode: episode, title: next.episodeTitle)
        guard var nextRequest = try? PlayerRequest(
            stream: stream,
            type: request.type,
            contentID: next.id,
            title: request.title.isEmpty ? showName ?? "" : request.title,
            logoURL: request.logoURL,
            startTime: TimeInterval(startTime ?? 0),
            continuation: continuation
        ) else { return nil }
        nextRequest.episodeLabel = label
        return UpNextEpisode(
            request: nextRequest,
            thumbnailURL: next.thumbnail.flatMap(URL.init(string:)),
            label: label
        )
    }

    /// The numbered episode after `contentID` in play order, across seasons; nil after the last one.
    static func nextEpisode(after contentID: String, in videos: [Video]) -> Video? {
        let episodes = SeasonQueueBuilder.orderedEpisodes(from: videos)
        guard let index = episodes.firstIndex(where: { $0.id == contentID }),
              episodes.indices.contains(index + 1) else { return nil }
        let nextID = episodes[index + 1].id
        return videos.first { $0.id == nextID }
    }
}
