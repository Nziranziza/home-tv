import Foundation

/// One addon catalog that can be filtered by genre.
struct GenreCatalogSource: Identifiable, Hashable, Sendable {
    let addon: InstalledAddon
    let catalog: CatalogDescriptor

    var id: String { "\(addon.id)::\(catalog.type)::\(catalog.id)" }
}
