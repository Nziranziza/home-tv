import Foundation

/// Derives the browsable genre list from the enabled addons' manifests, plus the naming and ordering
/// it's presented in. Addon names win over any baked-in list; `curatedOrder` only decides which lead.
enum GenreDirectory {
    private static let extraName = "genre"

    /// Genres that lead the row, in this order. Anything else an addon advertises follows,
    /// alphabetically.
    static let curatedOrder = [
        "Family", "Action", "Animation", "Comedy", "Drama", "Horror",
        "Sci-Fi", "Adventure", "Thriller", "Crime", "Romance", "Documentary",
        "Mystery", "Fantasy"
    ]

    /// Stand-in for a stale cached manifest that advertises no `genre` extra, since Cinemeta-shaped
    /// catalogs accept the extra regardless. Cinemeta's own names, so they work against it unchanged.
    static let fallback = curatedOrder.map { Genre(id: $0) }

    /// An explicit list rather than a hyphen-stripping rule, which would also mangle `Sci-Fi`.
    private static let displayOverrides = [
        "Reality-TV": "Reality TV",
        "Talk-Show": "Talk Show",
        "Game-Show": "Game Show"
    ]

    static func displayName(for id: String) -> String {
        displayOverrides[id] ?? id
    }

    static func advertisesGenres(_ catalog: CatalogDescriptor) -> Bool {
        genreOptions(in: catalog) != nil
    }

    /// Every distinct `genre` option the addons advertise, deduplicated case-insensitively and
    /// ordered. Empty — which hides the row — when no enabled addon exposes a catalog at all.
    static func genres(advertisedBy addons: [InstalledAddon]) -> [Genre] {
        var seen = Set<String>()
        var found: [Genre] = []

        for addon in addons {
            for catalog in addon.manifest.catalogs ?? [] {
                for option in genreOptions(in: catalog) ?? [] {
                    let trimmed = option.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
                    found.append(Genre(id: trimmed))
                }
            }
        }

        guard found.isEmpty else { return ordered(found) }
        // A stream-only addon list leaves the row hidden rather than offering dead tiles.
        let hasCatalogs = addons.contains { !($0.manifest.catalogs ?? []).isEmpty }
        return hasCatalogs ? fallback : []
    }

    /// The catalogs to query for a genre, one per addon and content type. Falls back to the first
    /// catalog of each type when nothing advertises the extra, matching `fallback`.
    static func catalogSources(in addons: [InstalledAddon]) -> [GenreCatalogSource] {
        let advertised = sources(in: addons) { advertisesGenres($0) }
        guard advertised.isEmpty else { return advertised }
        return sources(in: addons) { _ in true }
    }

    private static func sources(
        in addons: [InstalledAddon],
        where isEligible: (CatalogDescriptor) -> Bool
    ) -> [GenreCatalogSource] {
        var seen = Set<String>()
        var sources: [GenreCatalogSource] = []
        for addon in addons {
            for catalog in addon.manifest.catalogs ?? [] where isEligible(catalog) {
                guard seen.insert("\(addon.id)::\(catalog.type)").inserted else { continue }
                sources.append(GenreCatalogSource(addon: addon, catalog: catalog))
            }
        }
        return sources
    }

    /// A catalog's genre options, or nil if it has none worth showing. All-numeric option sets are
    /// rejected: Cinemeta's `year` catalogs advertise release years through this same extra.
    private static func genreOptions(in catalog: CatalogDescriptor) -> [String]? {
        for extra in catalog.extra ?? [] where extra.name.caseInsensitiveCompare(extraName) == .orderedSame {
            guard let options = extra.options, !options.isEmpty else { continue }
            guard !options.allSatisfy(isNumeric) else { continue }
            return options
        }
        return nil
    }

    private static func isNumeric(_ option: String) -> Bool {
        let trimmed = option.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.allSatisfy(\.isNumber)
    }

    private static func ordered(_ genres: [Genre]) -> [Genre] {
        let rank = Dictionary(
            uniqueKeysWithValues: curatedOrder.enumerated().map { ($0.element.lowercased(), $0.offset) }
        )
        return genres.sorted { lhs, rhs in
            switch (rank[lhs.id.lowercased()], rank[rhs.id.lowercased()]) {
            case let (lhsRank?, rhsRank?): lhsRank < rhsRank
            case (.some, .none): true
            case (.none, .some): false
            case (.none, .none): lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
        }
    }
}
