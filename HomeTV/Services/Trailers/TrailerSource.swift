import Foundation

/// Resolves a title's in-app-playable trailers from the **Trailerio** addon, when the user has it
/// installed. Returns an empty list (→ no autoplay; the existing static-image / YouTube behavior stands)
/// whenever Trailerio isn't installed, the id isn't an IMDb `tt…` id (Trailerio's only `idPrefixes`), or
/// the addon has nothing for the title.
///
/// This is the single gate for the whole trailer-autoplay feature: every hero asks `TrailerSource` for
/// candidates, and a `nil`/empty answer keeps that surface exactly as it was before.
@MainActor
enum TrailerSource {
    /// Trailerio's manifest id. Primary detection key; a host match is the fallback (see `installedAddon`).
    private static let manifestID = "io.trailerio.lite"

    /// The installed, enabled Trailerio addon, or nil. Matches by manifest id first, then falls back to
    /// any enabled addon served from a `trailerio` host (so a re-published manifest id still resolves).
    static var installedAddon: InstalledAddon? {
        installedAddon(in: AddonRegistry.shared.enabledAddons)
    }

    /// Same detection against an explicit addon list, so `syncTopShelfState(with:)` can run without
    /// re-entering the `AddonRegistry.shared` singleton (which it can't safely touch while that
    /// singleton is itself initializing).
    private static func installedAddon(in enabled: [InstalledAddon]) -> InstalledAddon? {
        if let byID = enabled.first(where: { $0.manifest.id == manifestID }) {
            return byID
        }
        return enabled.first { $0.manifestURL.host?.localizedStandardContains("trailerio") ?? false }
    }

    /// Mirror the enabled Trailerio addon's base URL (or nil) into the shared App Group so the
    /// out-of-process Top Shelf extension can resolve trailer autoplay URLs. `AddonRegistry` calls this
    /// whenever its addon list changes (and at launch); the list is passed in explicitly to keep this
    /// off the `AddonRegistry.shared` accessor. Trailerio detection and the shared-state key both live
    /// here, in the trailer feature, rather than leaking into the generic addon store.
    static func syncTopShelfState(with enabled: [InstalledAddon]) {
        TopShelfSharedState.trailerioBaseURL = installedAddon(in: enabled)?.baseURL
    }

    /// Whether trailer autoplay is available at all (the addon is installed). Cheap; safe to read on
    /// every hero render.
    static var isAvailable: Bool { installedAddon != nil }

    /// Per-session cache of resolved candidates, keyed by `type:showID`. The Watch Now hero re-asks on
    /// every auto-advance/page (and detail re-asks on every revisit), so without this the same title is
    /// re-fetched and re-decoded repeatedly. TTL is well under Trailerio's signed-URL lifetime.
    private struct CacheEntry { let date: Date; let candidates: [TrailerCandidate] }
    private static var cache: [String: CacheEntry] = [:]
    private static let cacheTTL: TimeInterval = 240

    /// Ordered, de-duplicated playable trailers for a title, best source first. Empty when unavailable.
    /// - `type`: Stremio type ("movie" / "series").
    /// - `id`: must be an IMDb id (`tt…`); a series episode id (`tt…:S:E`) is reduced to the show id.
    static func candidates(type: String, id: String) async -> [TrailerCandidate] {
        guard let addon = installedAddon else { return [] }
        let showID = TrailerResolver.showID(from: id)
        guard showID.hasPrefix("tt") else { return [] }

        let cacheKey = "\(type):\(showID)"
        if let entry = cache[cacheKey], Date().timeIntervalSince(entry.date) < cacheTTL {
            return entry.candidates
        }

        // The fetch-and-rank core is shared with the Top Shelf extension via `TrailerResolver`. A nil
        // result is a failure we don't cache (so it can be retried); a successful lookup — even an
        // empty one — is cached so repeated hero asks don't re-fetch the same title.
        guard let sorted = await TrailerResolver.candidates(baseURL: addon.baseURL, type: type, id: showID) else {
            return []
        }
        cache[cacheKey] = CacheEntry(date: Date(), candidates: sorted)
        return sorted
    }
}
