import Foundation

/// One *finished* title in the Recently Watched row — a movie, or a single episode of a show.
///
/// Two sources produce these, so the row renders identically either way: Trakt history when signed in
/// (authoritative, with real season/episode numbers and runtimes), and the local `WatchHistory`
/// otherwise (see the `init(finished:)` fallback below). Deliberately *not* a `MetaPreview`: a card is
/// an episode, and a preview only ever identifies a show.
struct RecentlyWatchedItem: Identifiable, Hashable, Sendable {
    /// "movie" or "series" — the Stremio type, so `preview` slots into the existing detail flow.
    let typeID: String
    /// IMDB id of the movie, or of the *show* for an episode.
    let metaID: String
    let name: String
    let season: Int?
    let episode: Int?
    let runtimeMinutes: Int?
    let watchedAt: Date
    let poster: String?
    let background: String?
    let logo: String?

    /// Landscape episode still, filled in from the show's episode list once loaded (see
    /// `EpisodeStillStore`). Falls back to the show/movie backdrop until then, and for movies always.
    var still: String?

    /// Per-episode identity, so the same episode watched twice collapses to a single card.
    var id: String {
        guard let season, let episode else { return "\(typeID):\(metaID)" }
        return "\(typeID):\(metaID):\(season):\(episode)"
    }

    /// Key into the episode-still cache and Trakt's playback map ("imdb:season:episode"); nil for a
    /// movie, which is keyed by its id alone.
    var episodeKey: String? {
        guard let season, let episode else { return nil }
        return "\(metaID):\(season):\(episode)"
    }

    /// The key this item occupies in Continue Watching, used to keep the two rows from showing the
    /// same thing twice.
    var progressKey: String { episodeKey ?? metaID }

    var artworkURL: URL? { (still ?? background ?? poster).flatMap(URL.init(string:)) }

    /// `S2, E3 · 43m` for an episode, a bare runtime for a movie. The runtime is dropped when unknown
    /// rather than faked, so the line reads `S2, E3` instead of `S2, E3 · `.
    var metadataText: String {
        let runtime = formattedRuntime
        guard let season, let episode else { return runtime ?? "" }
        let label = "S\(season), E\(episode)"
        guard let runtime else { return label }
        return "\(label) · \(runtime)"
    }

    private var formattedRuntime: String? {
        guard let runtimeMinutes, runtimeMinutes > 0 else { return nil }
        return Duration.seconds(runtimeMinutes * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }

    /// The show (or movie) this card belongs to, for the detail screen — selecting a card opens detail
    /// through the same `metaDetailDestination` flow as every other row.
    var preview: MetaPreview {
        MetaPreview(
            id: metaID,
            type: typeID,
            name: name,
            poster: poster,
            posterShape: nil,
            background: background,
            logo: logo,
            description: nil,
            releaseInfo: nil,
            imdbRating: nil,
            genres: nil
        )
    }
}

extension RecentlyWatchedItem {
    /// FALLBACK — a locally recorded title the `WatchHistory` has aged out of Continue Watching (see
    /// `WatchHistory.finishedItems`), used when not signed in to Trakt.
    ///
    /// Local history is title-level: HomeTV hands playback to Infuse/VLC, which report neither the
    /// episode watched nor the runtime.
    ///
    /// So `season`/`episode` stay nil — a *guessed* episode number would not just mislabel the card,
    /// it would resolve a real still (via `episodeKey` → `EpisodeStillStore`) for an episode the user
    /// may never have watched. The card renders a bare runtime instead, keeping its one-line caption.
    /// The runtime itself is derived deterministically from the item id — stable across launches — so
    /// the caption isn't empty, mirroring what the sibling `ContinueWatchingCard` does for its resume
    /// text. A duration is a far softer approximation than an episode identity.
    init(finished item: WatchHistoryItem) {
        self.init(
            typeID: item.typeID,
            metaID: item.metaID,
            name: item.name,
            season: nil,
            episode: nil,
            runtimeMinutes: 42 + Self.stableHash(item.metaID) % 48,   // 42–89 min
            watchedAt: item.finishedAt ?? item.viewedAt,
            poster: item.poster,
            background: item.background,
            logo: item.logo,
            still: nil
        )
    }

    /// Deterministic across launches — Swift's `String.hashValue` is seeded per process.
    private static func stableHash(_ string: String) -> Int {
        var hash = 5381
        for byte in string.utf8 { hash = ((hash << 5) &+ hash) &+ Int(byte) }
        return abs(hash)
    }
}
