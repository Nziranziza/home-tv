import Foundation
import Observation

/// Drives the Search screen. With no query it surfaces a "Browse" set drawn from the enabled addons'
/// default catalogs (popular/top content the user can wander through); once the user types, it runs a
/// multi-addon catalog search alongside a TMDB people search and splits the hits into the screen's
/// sections — Top Results, TV Shows, Movies, Cast & Crew. View-free so it can be unit-tested.
@Observable
@MainActor
final class SearchViewModel {
    private let registry: AddonRegistry
    private let client: StremioClient
    private let tmdb: TMDBService

    var query: String = ""
    private(set) var browseItems: [MetaPreview] = []
    /// Every catalog hit for the current query, already ranked — the sections below are slices of it.
    private(set) var results: [MetaPreview] = []
    private(set) var people: [CastPerson] = []
    private(set) var suggestions: [String] = []
    private(set) var status: Status = .browsing

    enum Status { case browsing, searching, results, empty }

    /// How many ranked hits lead the screen as Top Results — two rows of the reference frame's wide
    /// cards, which scroll horizontally beyond the six that fit.
    private static let topResultsLimit = 12

    // MARK: - Sections

    /// The strongest matches across every addon, regardless of type.
    var topResults: [MetaPreview] { Array(results.prefix(Self.topResultsLimit)) }
    var seriesResults: [MetaPreview] { results.filter { $0.type == "series" } }
    var movieResults: [MetaPreview] { results.filter { $0.type == "movie" } }

    /// True once the query is long enough that the suggestion row should show.
    var showsSuggestions: Bool { trimmedQuery.count >= 2 && !suggestions.isEmpty }

    /// Whether there is anything at all to render for the current query. Drives showing the previous
    /// sections (rather than a spinner) while a longer query is still in flight.
    var hasResults: Bool { !results.isEmpty || !people.isEmpty }

    var hasNoAddons: Bool { registry.enabledAddons.isEmpty }

    /// Everything a search depends on. The addon set is an input as much as the query is: it is
    /// seeded asynchronously at launch, so a search issued before it lands would otherwise sit on an
    /// empty result set with nothing to retry it. Views drive their `.task(id:)` off this.
    struct Inputs: Hashable {
        let query: String
        let addons: String
    }

    var searchInputs: Inputs { Inputs(query: query, addons: addonSignature) }

    /// Identity of the enabled addon set — each addon's id and manifest version, in order. A bare
    /// count would miss one addon being swapped for another, or an addon being updated in place,
    /// both of which change what a search returns.
    var addonSignature: String {
        registry.enabledAddons
            .map { "\($0.id)@\($0.manifest.version ?? "")" }
            .joined(separator: ",")
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    init(registry: AddonRegistry = .shared, client: StremioClient = .shared, tmdb: TMDBService = .shared) {
        self.registry = registry
        self.client = client
        self.tmdb = tmdb
    }

    /// Loads the Browse set from the first few default catalogs across enabled addons. Driven by a
    /// `.task(id: addonSignature)`, so it runs once per addon set and reloads whenever that set
    /// changes — the first call can land before any addon has been installed, and the catalogs
    /// behind Browse are different ones after an addon is added, removed or updated.
    func loadBrowse() async {
        let addons = addonSignature
        guard !hasNoAddons else {
            browseItems = []
            return
        }
        let collected = await fetch(catalogs: Array(defaultCatalogs.prefix(4)), extra: [:])
        // The addon set can change while the catalogs are in flight; a late reply from the previous
        // set must not overwrite what the current one loaded.
        guard addons == addonSignature else { return }
        browseItems = deduped(collected)
    }

    /// Runs whenever the query changes. Debounced; short queries reset to the Browse state.
    ///
    /// The previous sections are deliberately left standing while a new query is in flight — they are
    /// replaced only once the new hits have arrived, so growing the query a character at a time
    /// refreshes the rows in place instead of flashing through an empty screen.
    func runSearch() async {
        let trimmed = trimmedQuery
        let addons = addonSignature
        guard trimmed.count >= 2 else {
            clearResults()
            status = .browsing
            return
        }

        try? await Task.sleep(for: .milliseconds(400))
        if Task.isCancelled { return }
        if trimmed != trimmedQuery { return }

        status = .searching
        async let catalogHits = fetch(catalogs: searchableCatalogs, extra: ["search": trimmed])
        async let peopleHits = tmdb.searchPeople(query: trimmed)
        let (metas, cast) = await (catalogHits, peopleHits)
        // Drop a reply that outlived its query *or* its addon set — publishing hits gathered from
        // addons the user has since changed would show results the current set cannot explain.
        if Task.isCancelled || trimmed != trimmedQuery || addons != addonSignature { return }

        results = SearchRanker.rank(deduped(metas), query: trimmed)
        people = cast
        suggestions = SearchSuggestions.build(
            query: trimmed,
            titles: results.map(\.name),
            people: people.map(\.name)
        )
        status = hasResults ? .results : .empty
    }

    /// Replaces the query from a suggestion chip. The `.task(id:)` watching `query` re-runs the search.
    func apply(suggestion: String) {
        guard suggestion != query else { return }
        query = suggestion
    }

    private func clearResults() {
        results = []
        people = []
        suggestions = []
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
