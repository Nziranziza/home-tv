import Foundation
import Observation

/// Drives the Search screen. With no query it surfaces a "Browse" set drawn from the enabled addons'
/// default catalogs (popular/top content the user can wander through); once the user types, it runs
/// the same multi-addon search the screen has always done. View-free so it can be unit-tested.
@Observable
@MainActor
final class SearchViewModel {
    private let registry: AddonRegistry
    private let client: StremioClient

    var query: String = ""
    private(set) var browseItems: [MetaPreview] = []
    private(set) var results: [MetaPreview] = []
    private(set) var status: Status = .browsing

    enum Status { case browsing, searching, results, empty }

    /// What the grid should render: the live search when there's a query, otherwise the Browse set.
    var displayedItems: [MetaPreview] {
        query.trimmingCharacters(in: .whitespaces).count >= 2 ? results : browseItems
    }

    var hasNoAddons: Bool { registry.enabledAddons.isEmpty }

    init(registry: AddonRegistry = .shared, client: StremioClient = .shared) {
        self.registry = registry
        self.client = client
    }

    /// Loads the Browse set from the first few default catalogs across enabled addons. Cheap to call
    /// repeatedly — the client caches each fetch.
    func loadBrowse() async {
        guard browseItems.isEmpty else { return }
        let collected = await fetch(catalogs: Array(defaultCatalogs.prefix(4)), extra: [:])
        browseItems = deduped(collected)
    }

    /// Runs whenever the query changes. Debounced; short queries reset to the Browse state.
    func runSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            status = .browsing
            return
        }

        try? await Task.sleep(for: .milliseconds(400))
        if Task.isCancelled { return }
        if trimmed != query.trimmingCharacters(in: .whitespaces) { return }

        status = .searching
        let collected = await fetch(catalogs: searchableCatalogs, extra: ["search": trimmed])
        results = deduped(collected)
        status = results.isEmpty ? .empty : .results
    }

    // MARK: - Catalog selection

    private var defaultCatalogs: [(addon: InstalledAddon, catalog: CatalogDescriptor)] {
        registry.enabledAddons.flatMap { addon in
            (addon.manifest.catalogs ?? []).map { (addon, $0) }
        }
    }

    private var searchableCatalogs: [(addon: InstalledAddon, catalog: CatalogDescriptor)] {
        registry.enabledAddons.flatMap { addon in
            (addon.manifest.catalogs ?? [])
                .filter { $0.extra?.contains(where: { $0.name == "search" }) ?? false }
                .map { (addon, $0) }
        }
    }

    // MARK: - Fetching

    private func fetch(
        catalogs: [(addon: InstalledAddon, catalog: CatalogDescriptor)],
        extra: [String: String]
    ) async -> [MetaPreview] {
        await withTaskGroup(of: [MetaPreview].self) { group in
            for (addon, catalog) in catalogs {
                group.addTask { [client] in
                    do {
                        let response = try await client.catalog(
                            baseURL: addon.baseURL,
                            type: catalog.type,
                            id: catalog.id,
                            extra: extra
                        )
                        return response.metas
                    } catch {
                        return []
                    }
                }
            }
            var all: [MetaPreview] = []
            for await batch in group { all.append(contentsOf: batch) }
            return all
        }
    }

    private func deduped(_ metas: [MetaPreview]) -> [MetaPreview] {
        var seen: Set<String> = []
        return metas.filter { seen.insert($0.id).inserted }
    }
}
