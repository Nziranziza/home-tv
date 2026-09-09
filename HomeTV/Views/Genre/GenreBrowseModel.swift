import Foundation
import Observation

/// Loads one genre's titles, merged across every enabled addon. Movies and series land in a single
/// grid, round-robined rather than concatenated so each catalog keeps its own popularity ranking.
@Observable
@MainActor
final class GenreBrowseModel {
    enum Status { case idle, loading, loaded, empty, failed }

    let genre: Genre

    private let registry: AddonRegistry
    private let client: StremioClient

    private(set) var items: [MetaPreview] = []
    private(set) var status: Status = .idle

    init(genre: Genre, registry: AddonRegistry = .shared, client: StremioClient = .shared) {
        self.genre = genre
        self.registry = registry
        self.client = client
    }

    func load() async {
        guard status == .idle else { return }
        status = .loading

        let sources = GenreDirectory.catalogSources(in: registry.enabledAddons)
        guard !sources.isEmpty else {
            status = .empty
            return
        }

        let pages = await Self.pages(for: genre, sources: sources, client: client)
        guard !pages.isEmpty else {
            status = .failed
            return
        }

        items = Self.merge(pages)
        status = items.isEmpty ? .empty : .loaded
    }

    /// Drops repeats by id, so a title carried by two addons appears once, at its best position.
    static func merge(_ pages: [[MetaPreview]]) -> [MetaPreview] {
        var merged: [MetaPreview] = []
        var seen = Set<String>()
        let deepest = pages.map(\.count).max() ?? 0
        for index in 0..<deepest {
            for page in pages where index < page.count {
                let meta = page[index]
                guard seen.insert(meta.id).inserted else { continue }
                merged.append(meta)
            }
        }
        return merged
    }

    /// Fetched concurrently but returned in catalog order, so the merge is deterministic. Catalogs
    /// that fail are dropped; an empty result means every fetch failed.
    private nonisolated static func pages(
        for genre: Genre,
        sources: [GenreCatalogSource],
        client: StremioClient
    ) async -> [[MetaPreview]] {
        await withTaskGroup(of: (Int, [MetaPreview]?).self) { group in
            for (index, source) in sources.enumerated() {
                group.addTask {
                    let response = try? await client.catalog(
                        baseURL: source.addon.baseURL,
                        type: source.catalog.type,
                        id: source.catalog.id,
                        extra: ["genre": genre.id]
                    )
                    return (index, response?.metas)
                }
            }

            var byIndex: [Int: [MetaPreview]] = [:]
            for await (index, metas) in group {
                if let metas { byIndex[index] = metas }
            }
            return sources.indices.compactMap { byIndex[$0] }
        }
    }
}
