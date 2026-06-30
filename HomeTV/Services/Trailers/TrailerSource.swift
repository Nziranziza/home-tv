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
        let enabled = AddonRegistry.shared.enabledAddons
        if let byID = enabled.first(where: { $0.manifest.id == manifestID }) {
            return byID
        }
        return enabled.first { $0.manifestURL.host?.localizedStandardContains("trailerio") ?? false }
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
        let showID = String(id.split(separator: ":").first ?? Substring(id))
        guard showID.hasPrefix("tt") else { return [] }

        let cacheKey = "\(type):\(showID)"
        if let entry = cache[cacheKey], Date().timeIntervalSince(entry.date) < cacheTTL {
            return entry.candidates
        }

        let response: TrailerioMetaResponse
        do {
            // Trailerio answers the standard `meta` path but with a non-standard `meta.links` payload.
            response = try await StremioClient.shared.fetch(
                baseURL: addon.baseURL,
                segments: ["meta", type, showID],
                as: TrailerioMetaResponse.self
            )
        } catch {
            return []   // best-effort: any failure simply yields no autoplay (don't cache failures)
        }

        // Guard against a mismatched response (wrong title) before caching/returning. Only the id is
        // checked: Trailerio echoes the requested tt id exactly, whereas `type` is optional and may be
        // omitted, so a type equality check could wrongly reject a valid response.
        guard response.meta.id == showID else { return [] }

        var seen = Set<String>()
        let candidates = (response.meta.links ?? [])
            .compactMap { link -> TrailerCandidate? in
                guard let url = URL(string: link.trailers) else { return nil }
                guard seen.insert(url.absoluteString).inserted else { return nil }
                return TrailerCandidate(url: url, provider: link.provider ?? "Trailer")
            }
        // Stable sort by source preference: enumerate so equal ranks keep Trailerio's original order.
        let sorted = candidates
            .enumerated()
            .sorted { (providerRank($0.element.provider), $0.offset) < (providerRank($1.element.provider), $1.offset) }
            .map(\.element)
        cache[cacheKey] = CacheEntry(date: Date(), candidates: sorted)
        return sorted
    }

    /// Source preference, lower = tried first. The ⭐/Plex pick (Trailerio's own curated, reliably
    /// direct-mp4 source) leads, then any 1080p source, then everything else — all kept as fallbacks the
    /// player walks if one fails. Ties preserve Trailerio's original order (a stable sort via the index).
    private static func providerRank(_ provider: String) -> Int {
        if provider.contains("⭐") || provider.localizedStandardContains("plex") { return 0 }
        if provider.localizedStandardContains("1080") { return 1 }
        return 2
    }
}
