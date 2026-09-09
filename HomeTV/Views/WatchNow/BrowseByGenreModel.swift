import Foundation
import Observation

/// Drives the Browse by Genre row: the genre list, and one representative poster per genre.
///
/// Artwork resolves in two phases, so a twenty-tile row doesn't fire twenty requests: first mine the
/// catalog pages the screen already fetched (their `metas` carry `genres`, and the client caches by
/// URL, so this is free), then fetch genre-filtered catalogs only for what's left.
@Observable
@MainActor
final class BrowseByGenreModel {
    /// Small on purpose: gap fills for a decorative tile must not compete with the fetches the user is
    /// actually waiting on.
    private static let artworkFetchConcurrency = 3

    /// Keeps alternatives for a genre whose top title is already claimed by another tile.
    private static let posterCandidateDepth = 6

    private let registry: AddonRegistry
    private let client: StremioClient

    /// Keyed by the lowercased genre id.
    private(set) var artwork: [String: URL] = [:]

    init(registry: AddonRegistry = .shared, client: StremioClient = .shared) {
        self.registry = registry
        self.client = client
    }

    /// Computed, like `WatchNowViewModel.rowSpecs`, so toggling an addon updates the row.
    var genres: [Genre] { GenreDirectory.genres(advertisedBy: registry.enabledAddons) }

    /// Re-fires artwork resolution only when the genres actually change.
    var artworkRequestKey: String { genres.map(\.id).joined(separator: ",") }

    func artworkURL(for genre: Genre) -> URL? { artwork[genre.id.lowercased()] }

    func loadArtwork() async {
        let requestKey = artworkRequestKey
        let genres = self.genres
        let sources = GenreDirectory.catalogSources(in: registry.enabledAddons)
        guard !genres.isEmpty, !sources.isEmpty else { return }

        let pages = await unfilteredPages(sources: sources)
        var resolved = Self.assignPosters(genres: genres, pages: pages)
        guard publish(resolved, for: requestKey) else { return }

        let missing = genres.filter { resolved[$0.id.lowercased()] == nil }
        guard !missing.isEmpty else { return }

        // Sources per genre, resolved here on the main actor: only the catalogs that advertise a genre
        // are asked for it.
        let requests = missing.map { genre in
            (genre, GenreDirectory.catalogSources(in: registry.enabledAddons, for: genre))
        }
        let candidates = await Self.posterCandidates(for: requests, client: client)

        var used = Set(resolved.values)
        for genre in missing {
            let key = genre.id.lowercased()
            guard let poster = (candidates[key] ?? []).first(where: { !used.contains($0) }) else { continue }
            resolved[key] = poster
            used.insert(poster)
        }
        _ = publish(resolved, for: requestKey)
    }

    /// Publishes a result only if it is still the one being asked for. A `.task(id:)` restart cancels
    /// the previous load, but a cancelled task still runs to its next suspension — so without this an
    /// in-flight load could finish after its replacement and overwrite it with the old addons' posters.
    private func publish(_ resolved: [String: URL], for requestKey: String) -> Bool {
        guard !Task.isCancelled, requestKey == artworkRequestKey else { return false }
        artwork = resolved
        return true
    }

    private func unfilteredPages(sources: [GenreCatalogSource]) async -> [[MetaPreview]] {
        var pages: [[MetaPreview]] = []
        for source in sources {
            guard let response = try? await client.catalog(
                baseURL: source.addon.baseURL,
                type: source.catalog.type,
                id: source.catalog.id
            ) else { continue }
            pages.append(response.metas)
        }
        return pages
    }

    /// A poster per genre from the unfiltered pages — `metas` are ranked by popularity, so the first
    /// title tagged with a genre is a reasonable face for it. A poster is claimed by at most one genre:
    /// popular titles carry several, and one filling three neighbouring tiles is obvious on screen.
    static func assignPosters(genres: [Genre], pages: [[MetaPreview]]) -> [String: URL] {
        var resolved: [String: URL] = [:]
        var used = Set<URL>()

        for genre in genres {
            var poster: URL?
            for meta in pages.joined() {
                guard meta.genres?.contains(where: { $0.caseInsensitiveCompare(genre.id) == .orderedSame }) == true,
                      let candidate = meta.poster.flatMap(URL.init(string:)),
                      !used.contains(candidate)
                else { continue }
                poster = candidate
                break
            }

            guard let poster else { continue }
            resolved[genre.id.lowercased()] = poster
            used.insert(poster)
        }
        return resolved
    }

    /// Genre-filtered fetches for what phase 1 missed. Returns several candidates per genre so the
    /// caller can skip one already claimed. `nonisolated` so the fetches run off the main actor.
    private nonisolated static func posterCandidates(
        for requests: [(genre: Genre, sources: [GenreCatalogSource])],
        client: StremioClient
    ) async -> [String: [URL]] {
        let fetch: @Sendable ((genre: Genre, sources: [GenreCatalogSource])) async -> (String, [URL]) = { request in
            let genre = request.genre
            var candidates: [URL] = []
            for source in request.sources {
                guard let response = try? await client.catalog(
                    baseURL: source.addon.baseURL,
                    type: source.catalog.type,
                    id: source.catalog.id,
                    extra: ["genre": genre.id]
                ) else { continue }
                candidates += response.metas
                    .prefix(posterCandidateDepth)
                    .compactMap { $0.poster.flatMap(URL.init(string:)) }
                if !candidates.isEmpty { break }
            }
            return (genre.id.lowercased(), candidates)
        }

        return await withTaskGroup(of: (String, [URL]).self) { group in
            var next = min(artworkFetchConcurrency, requests.count)
            for request in requests.prefix(next) {
                group.addTask { await fetch(request) }
            }

            var resolved: [String: [URL]] = [:]
            while let (key, candidates) = await group.next() {
                resolved[key] = candidates
                if next < requests.count {
                    let request = requests[next]
                    next += 1
                    group.addTask { await fetch(request) }
                }
            }
            return resolved
        }
    }
}
