import Foundation

/// Pure, actor-agnostic resolution of a title's playable trailers from a **Trailerio**-style addon,
/// given its base URL. This is the fetch-and-rank core shared by the in-app `TrailerSource` (which
/// supplies the base URL from the user's installed addons and layers a cache on top) and the Top Shelf
/// extension (which reads the base URL from `TopShelfSharedState`).
///
/// Kept `nonisolated` and free of app/main-actor state so both the `@MainActor` app and the
/// out-of-process extension can call it directly.
enum TrailerResolver {
    /// Ordered, de-duplicated playable trailers for a title, best source first.
    ///
    /// Returns `nil` on **failure** (bad id, transport/decode error, or a mismatched response) so the
    /// caller can decline to cache it and retry later; returns a possibly-**empty** array when the
    /// addon answered successfully but has nothing for the title (safe to cache — it won't change).
    /// - `baseURL`: the Trailerio addon base URL.
    /// - `type`: Stremio type ("movie" / "series").
    /// - `id`: IMDb id (`tt…`); a series episode id (`tt…:S:E`) is reduced to the show id.
    static func candidates(baseURL: URL, type: String, id: String) async -> [TrailerCandidate]? {
        let showID = Self.showID(from: id)
        guard showID.hasPrefix("tt") else { return nil }

        let response: TrailerioMetaResponse
        do {
            // Trailerio answers the standard `meta` path but with a non-standard `meta.links` payload.
            response = try await StremioClient.shared.fetch(
                baseURL: baseURL,
                segments: ["meta", type, showID],
                as: TrailerioMetaResponse.self
            )
        } catch {
            return nil   // best-effort: any failure simply yields no autoplay
        }

        // Guard against a mismatched response (wrong title). Only the id is checked: Trailerio echoes
        // the requested tt id exactly, whereas `type` is optional and may be omitted, so a type
        // equality check could wrongly reject a valid response.
        guard response.meta.id == showID else { return nil }

        var seen = Set<String>()
        let candidates = (response.meta.links ?? [])
            .compactMap { link -> TrailerCandidate? in
                guard let url = URL(string: link.trailers) else { return nil }
                guard seen.insert(url.absoluteString).inserted else { return nil }
                return TrailerCandidate(url: url, provider: link.provider ?? "Trailer")
            }
        // Stable sort by source preference: enumerate so equal ranks keep Trailerio's original order.
        return candidates
            .enumerated()
            .sorted { (providerRank($0.element.provider), $0.offset) < (providerRank($1.element.provider), $1.offset) }
            .map(\.element)
    }

    /// Reduces a Stremio id to its show id: an episode id (`tt…:S:E`) becomes the base `tt…`. Shared
    /// with `TrailerSource`, which keys its per-session cache by the same reduced id.
    static func showID(from id: String) -> String {
        String(id.split(separator: ":").first ?? Substring(id))
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
