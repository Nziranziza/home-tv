import Foundation
import Observation

/// Episode stills for the Recently Watched row, keyed "imdb:season:episode".
///
/// Trakt tells us *which* episode was finished but carries no artwork, and Metahub only has show-level
/// backdrops — so every episode of a show would otherwise look identical. The addon's own episode list
/// does have per-episode thumbnails, so this fetches each show's meta (the `StremioClient` caches
/// and coalesces, so a show already opened on a detail screen costs nothing) and indexes its
/// thumbnails. Until a show resolves, its cards fall back to the show backdrop.
@Observable
@MainActor
final class EpisodeStillStore {
    private(set) var stills: [String: String] = [:]

    /// Shows whose fetch has been *claimed*, so concurrent passes don't refetch the same show. Claimed
    /// in `loadShow` as the fetch begins and released again if it resolves nothing — a show is only
    /// held for good once its stills are in `stills`. Observation-ignored: bookkeeping, not something a
    /// view reads.
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

        // Each batch runs concurrently — these are independent network fetches, and doing them all in
        // series would trickle the stills in one show at a time. Shows are claimed per fetch (in
        // `loadShow`) rather than all up front, so cancelling this task — which `.task(id:)` does the
        // moment the row's shows change — leaves the batches that never ran free for its replacement.
        var start = pending.startIndex
        while start < pending.endIndex {
            if Task.isCancelled { return }
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
        guard requestedShows.insert(imdb).inserted else { return }
        for addon in AddonRegistry.shared.enabledAddons {
            // A cancelled fetch surfaces as a nil result below, which would otherwise fall through to
            // the next addon and fire another doomed request. Stop at the first sign of cancellation
            // and release the claim so the replacement task can pick this show up.
            if Task.isCancelled {
                requestedShows.remove(imdb)
                return
            }
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
        // Resolved nothing — cancelled mid-flight, every addon failed, or none had thumbnails. Release
        // the claim either way: these cards are sitting on the show backdrop, so the next pass (a rare
        // event — only a change to the row's shows re-fires it) should be free to try again.
        requestedShows.remove(imdb)
    }
}
