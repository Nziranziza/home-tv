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
        // UI tests need a hero of known length that no network hiccup can shorten (see MOCK_HERO), the
        // same launch-environment escape hatch INITIAL_DETAIL and MOCK_STREAMS use.
        if let mocked = Self.mockedHeroItems {
            heroItems = mocked
            return
        }
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

    /// Featured titles injected by MOCK_HERO=<count>, so UI tests exercising the hero carousel do not
    /// depend on a live catalog. Nil unless the variable is set.
    private static var mockedHeroItems: [MetaPreview]? {
        guard let raw = ProcessInfo.processInfo.environment["MOCK_HERO"],
              let count = Int(raw), count > 0 else { return nil }
        return (1...count).map {
            .placeholder(type: "movie", id: "tt-mock-\($0)", name: "Mock Title \($0)")
        }
    }
}
