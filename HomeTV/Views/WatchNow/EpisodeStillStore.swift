import Foundation
import Observation

/// Episode stills for the Recently Watched row, keyed "imdb:season:episode".
///
/// Trakt tells us *which* episode was finished but carries no artwork, and Metahub only has show-level
/// backdrops — so every episode of a show would otherwise look identical. The addon's own episode list
/// does have per-episode thumbnails, so this fetches each show's meta once (the `StremioClient` caches
/// and coalesces, so a show already opened on a detail screen costs nothing) and indexes its
/// thumbnails. Until a show resolves, its cards fall back to the show backdrop.
@Observable
@MainActor
final class EpisodeStillStore {
    private(set) var stills: [String: String] = [:]

    /// Shows already fetched (successfully or not), so a re-render never refetches. Observation-ignored:
    /// it's bookkeeping, not something a view reads.
    @ObservationIgnored private var requestedShows: Set<String> = []

    /// How many meta fetches are in flight at once. A cap on *concurrency*, not on how many shows get
    /// loaded: every pending show is fetched, in batches, so a row spanning more shows than this still
    /// ends up fully resolved — it just doesn't fire the whole burst on the first render.
    private static let maxConcurrentShows = 8

    /// Load stills for any show in `items` we haven't fetched yet. Cheap and idempotent — safe to call
    /// from a `.task(id:)` that re-fires as the row's items change.
    func load(for items: [RecentlyWatchedItem]) async {
        var pending: [String] = []
        for item in items where item.episodeKey != nil {
            guard !requestedShows.contains(item.metaID), !pending.contains(item.metaID) else { continue }
            pending.append(item.metaID)
        }
        guard !pending.isEmpty else { return }
        requestedShows.formUnion(pending)

        // Each batch runs concurrently — these are independent network fetches, and doing them all in
        // series would trickle the stills in one show at a time.
        var start = pending.startIndex
        while start < pending.endIndex {
            let end = min(start + Self.maxConcurrentShows, pending.endIndex)
            await withTaskGroup(of: Void.self) { group in
                for show in pending[start..<end] {
                    group.addTask { await self.loadShow(show) }
                }
            }
            start = end
        }
    }

    private func loadShow(_ imdb: String) async {
        for addon in AddonRegistry.shared.enabledAddons {
            guard let response = try? await StremioClient.shared.meta(
                baseURL: addon.baseURL,
                type: "series",
                id: imdb
            ) else { continue }

            var found: [String: String] = [:]
            for video in response.meta.videos ?? [] {
                guard let season = video.season,
                      let episode = video.episode,
                      let thumbnail = video.thumbnail else { continue }
                found["\(imdb):\(season):\(episode)"] = thumbnail
            }
            // Meta without usable thumbnails is no answer at all — keep asking the remaining addons
            // rather than settling for the show backdrop.
            guard !found.isEmpty else { continue }
            stills.merge(found) { _, new in new }
            return
        }
    }
}
