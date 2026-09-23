import Foundation

/// Turns "the user picked this stream for this episode" into an ordered season queue for an external
/// player. Pure and synchronous — the add-on requests live in `SeasonQueuePrefetcher` — so every
/// matching and ordering rule below is unit-testable without a network or a view.
enum SeasonQueueBuilder {

    /// Maximum items in one hand-off, sized to cover whole multi-season packs. Not a URL limit: a
    /// 2000-item, 620 KB hand-off opens fine on an Apple TV. In practice the pack binds first, since
    /// the queue stops at the first episode the chosen release does not cover.
    static let maxEntries = 100

    /// A stream an add-on returned for one episode. Keyed by installed id, not display name, which the
    /// registry never promised to be unique.
    struct Candidate: Hashable, Sendable {
        let stream: Stream
        let addonID: String
    }

    /// One numbered episode of the show, normalised out of `Meta.videos`.
    struct Episode: Hashable, Sendable {
        let id: String
        let season: Int
        let episode: Int
        /// The episode's own title, when the add-on has one. It goes into the filename so an entry
        /// Infuse has not matched yet still reads as the episode rather than as a bare number.
        var title: String?
    }

    /// An episode paired with the stream that continues the selected release.
    struct Resolved: Hashable, Sendable {
        let episode: Episode
        let stream: Stream
    }

    /// What makes two episodes' streams the same release: the add-on's own `bingeGroup`, or literally
    /// the same torrent. Nothing weaker — a near-match risks queueing the wrong cut.
    enum ReleaseIdentity: Hashable, Sendable {
        case bingeGroup(String)
        case infoHash(String)
    }

    static func identities(of stream: Stream) -> Set<ReleaseIdentity> {
        var result: Set<ReleaseIdentity> = []
        let group = stream.behaviorHints?.bingeGroup?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let group, !group.isEmpty { result.insert(.bingeGroup(group)) }
        let hash = stream.infoHash?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let hash, !hash.isEmpty { result.insert(.infoHash(hash.lowercased())) }
        return result
    }

    // MARK: - Episode list

    /// The show's episodes in play order, across every season. Specials and unnumbered videos are
    /// dropped, since a pack's file numbering rarely lines up with them. Season boundaries are not
    /// special: a complete-series pack rolls the queue into the next season.
    static func orderedEpisodes(from videos: [Video]) -> [Episode] {
        var seen: Set<String> = []
        var result: [Episode] = []
        for video in videos {
            guard let season = video.season, season > 0, let episode = video.episode else { continue }
            guard seen.insert(video.id).inserted else { continue }
            result.append(Episode(id: video.id, season: season, episode: episode, title: video.episodeTitle))
        }
        result.sort { ($0.season, $0.episode) < ($1.season, $1.episode) }
        return result
    }

    // MARK: - Ordering

    /// Walks out from the selected episode in both directions while the same release keeps turning up,
    /// stopping at the first gap rather than hopping over it — a hole means the release ended there.
    ///
    /// The result is rotated: the selected episode, forward to where the release runs out, then the
    /// contiguous run behind it in ascending order.
    static func assemble(
        episodes: [Episode],
        selectedIndex: Int,
        limit: Int = maxEntries,
        stream: (Episode) -> Stream?
    ) -> [Resolved] {
        guard episodes.indices.contains(selectedIndex), limit > 0 else { return [] }

        var forward: [Resolved] = []
        for index in selectedIndex..<episodes.count {
            guard let match = stream(episodes[index]) else { break }
            forward.append(Resolved(episode: episodes[index], stream: match))
            if forward.count == limit { return forward }
        }
        // The selected episode always leads; if even it has no stream there is no queue.
        guard !forward.isEmpty else { return [] }

        var backward: [Resolved] = []
        for index in stride(from: selectedIndex - 1, through: 0, by: -1) {
            guard let match = stream(episodes[index]) else { break }
            backward.append(Resolved(episode: episodes[index], stream: match))
            if forward.count + backward.count == limit { break }
        }
        return forward + backward.reversed()
    }

    // MARK: - Matching

    /// The candidate for `episode` that continues the selected release. Magnet-only and uncached
    /// debrid streams are rejected even when the release matches: neither is ready to play.
    static func sameRelease(
        as identities: Set<ReleaseIdentity>,
        addonID: String,
        among candidates: [Candidate]
    ) -> Stream? {
        guard !identities.isEmpty, !addonID.isEmpty else { return nil }
        for candidate in candidates where candidate.addonID == addonID {
            guard !identities.isDisjoint(with: self.identities(of: candidate.stream)) else { continue }
            guard isQueueable(candidate.stream) else { continue }
            return candidate.stream
        }
        return nil
    }

    /// A direct http(s) URL whose debrid link, if any, is already cached.
    static func isQueueable(_ stream: Stream) -> Bool {
        guard let raw = stream.url, let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        let label = "\(stream.name ?? "") \(stream.title ?? "")"
        if let debrid = DebridInfo.parse(from: label), !debrid.isCached { return false }
        return true
    }

    // MARK: - Assembly

    /// The ordered hand-off for a chosen stream, or nil when there is nothing to queue beyond the
    /// selected episode. Nil means launch as before; it is not a failure.
    static func queue(
        showID: String,
        showName: String,
        runtimeSeconds: Int? = nil,
        episodes: [Episode],
        selectedEpisodeID: String,
        selectedStream: Stream,
        addonID: String,
        candidates: [String: [Candidate]],
        limit: Int = maxEntries
    ) -> PlaybackQueue? {
        guard let selectedIndex = episodes.firstIndex(where: { $0.id == selectedEpisodeID }) else { return nil }
        guard isQueueable(selectedStream) else { return nil }
        let identities = identities(of: selectedStream)
        guard !identities.isEmpty else { return nil }

        let resolved = assemble(episodes: episodes, selectedIndex: selectedIndex, limit: limit) { episode in
            if episode.id == selectedEpisodeID { return selectedStream }
            return sameRelease(as: identities, addonID: addonID, among: candidates[episode.id] ?? [])
        }
        guard resolved.count > 1 else { return nil }

        let entries = resolved.compactMap { item -> PlaybackQueueEntry? in
            guard let raw = item.stream.url, let url = URL(string: raw) else { return nil }
            return PlaybackQueueEntry(
                episodeID: item.episode.id,
                season: item.episode.season,
                episode: item.episode.episode,
                url: url,
                filename: PlayerFilename.episode(
                    showName: showName,
                    season: item.episode.season,
                    episode: item.episode.episode,
                    episodeTitle: item.episode.title,
                    url: url
                ),
                runtimeSeconds: runtimeSeconds
            )
        }
        guard entries.count > 1 else { return nil }
        return PlaybackQueue(showID: showID, showName: showName, entries: entries)
    }
}
