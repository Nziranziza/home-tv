import Foundation
import Observation

/// Owns the Watch Now screen's hero state and the derived list of catalog rows. Rows still load
/// lazily as they scroll into view (via `ContentRow`); the `StremioClient` cache means the hero and
/// the first row share a single network fetch.
@Observable
@MainActor
final class WatchNowViewModel {
    private let registry: AddonRegistry
    private let client: StremioClient

    private(set) var heroItems: [MetaPreview] = []

    init(registry: AddonRegistry = .shared, client: StremioClient = .shared) {
        self.registry = registry
        self.client = client
    }

    /// One row per catalog across every enabled addon.
    var rowSpecs: [ContentRowSpec] {
        registry.enabledAddons.flatMap { addon in
            (addon.manifest.catalogs ?? []).map { ContentRowSpec(addon: addon, catalog: $0) }
        }
    }

    var hasNoAddons: Bool { registry.enabledAddons.isEmpty }

    /// Loads the hero from the first catalog. Cheap to call repeatedly — the client caches the fetch.
    func loadHero() async {
        guard let first = rowSpecs.first else {
            heroItems = []
            return
        }
        do {
            let response = try await client.catalog(
                baseURL: first.addon.baseURL,
                type: first.catalog.type,
                id: first.catalog.id
            )
            heroItems = Array(response.metas.prefix(6))
        } catch {
            heroItems = []
        }
    }
}
