import Foundation

/// Derives the browsable genre list from the enabled addons' manifests, plus the naming and ordering
/// it's presented in. Addon names win over any baked-in list; `curatedOrder` only decides which lead.
///
/// Strictly advertised: a genre is offered only if some catalog says it accepts it, and is only ever
/// queried against the catalogs that said so. A curated stand-in list was tried and removed — an addon
/// that quietly ignores an undeclared `genre` extra returns the same unfiltered page for every tile,
/// which is worse than not offering the row.
enum GenreDirectory {
    private static let extraName = "genre"

    /// Genres that lead the row, in this order. Anything else an addon advertises follows,
    /// alphabetically.
    static let curatedOrder = [
        "Family", "Action", "Animation", "Comedy", "Drama", "Horror",
        "Sci-Fi", "Adventure", "Thriller", "Crime", "Romance", "Documentary",
        "Mystery", "Fantasy"
    ]

    /// An explicit list rather than a hyphen-stripping rule, which would also mangle `Sci-Fi`.
    private static let displayOverrides = [
        "Reality-TV": "Reality TV",
        "Talk-Show": "Talk Show",
        "Game-Show": "Game Show"
    ]

    static func displayName(for id: String) -> String {
        displayOverrides[id] ?? id
    }

    /// Every distinct `genre` option the addons advertise, deduplicated case-insensitively and
    /// ordered. Empty — which hides the row — when nothing advertises the extra.
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

        return ordered(found)
    }

    /// The catalogs to query for one genre: the first per addon and content type that advertises it.
    ///
    /// Per genre, not per addon — `genres(advertisedBy:)` unions the options across every catalog, so a
    /// genre only some of them accept (Cinemeta advertises Reality-TV on series but not on movies) would
    /// otherwise be sent to a catalog that never claimed to support it, or be dropped when the catalog
    /// that does support it isn't the first of its type.
    static func catalogSources(in addons: [InstalledAddon], for genre: Genre) -> [GenreCatalogSource] {
        sources(in: addons) { catalog in
            genreOptions(in: catalog)?.contains {
                $0.caseInsensitiveCompare(genre.id) == .orderedSame
            } == true
        }
    }

    /// The genre-capable catalogs, one per addon and content type, for reading *unfiltered* pages —
    /// which is all the Browse by Genre row needs to pick tile artwork out of them.
    static func catalogSources(in addons: [InstalledAddon]) -> [GenreCatalogSource] {
        sources(in: addons) { genreOptions(in: $0) != nil }
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
