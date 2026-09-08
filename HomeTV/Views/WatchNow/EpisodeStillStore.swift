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

    /// Shows resolved per pass. The row shows ~20 cards over a handful of distinct shows; this caps the
    /// burst of meta requests a first render can fire.
    private static let maxShowsPerPass = 8

    /// Load stills for any show in `items` we haven't fetched yet. Cheap and idempotent — safe to call
    /// from a `.task(id:)` that re-fires as the row's items change.
    func load(for items: [RecentlyWatchedItem]) async {
        var pending: [String] = []
        for item in items where item.episodeKey != nil {
            guard !requestedShows.contains(item.metaID), !pending.contains(item.metaID) else { continue }
            pending.append(item.metaID)
            if pending.count == Self.maxShowsPerPass { break }
        }
        guard !pending.isEmpty else { return }
        requestedShows.formUnion(pending)

        // Concurrently — these are independent network fetches, and doing them in series would trickle
        // the stills in one show at a time.
        await withTaskGroup(of: Void.self) { group in
            for show in pending {
                group.addTask { await self.loadShow(show) }
            }
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
            guard !found.isEmpty else { return }
            stills.merge(found) { _, new in new }
            return
        }
    }
}
