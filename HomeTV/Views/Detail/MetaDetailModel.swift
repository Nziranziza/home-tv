import Foundation

/// Owns the detail screen's content state (loaded meta, TMDB enrichment, related titles, per-season
/// episode info) and the *expensive* derivations that must not be recomputed on every render.
///
/// Marked `@MainActor @Observable` (the project applies strict concurrency with no default actor
/// isolation): the section views observe it and re-render only when the specific properties they read
/// actually change.
///
/// The heavy season/episode derivations are cached (`sortedEpisodes`, `seasons`,
/// `seasonFirstEpisodeID`) and recomputed only when `meta` changes — not on every scroll frame as the
/// old per-render `MetaDetailViewModel` rebuild did. All the cheap presentation logic (display
/// strings, credits, providers, hero facts, formatting) is delegated to the pure, unit-testable
/// `MetaDetailViewModel` value via `vm`.
@MainActor
@Observable
final class MetaDetailModel {
    enum LoadStatus { case loading, loaded, failed }

    let typeID: String
    let metaID: String
    let fallbackTitle: String
    /// Preview/sample injection only (see `#Preview`); nil in the app, where `load()` fetches from addons.
    private let previewMeta: Meta?

    /// Base meta from the addon. Recomputes the cached episode + credit/watch derivations when it changes.
    var meta: Meta? { didSet { recomputeEpisodes(); recomputeDerived() } }
    /// TMDB enrichment sidecar, populated after the base meta loads. nil until then (or when TMDB
    /// isn't configured / the id isn't an IMDB id) — every consumer falls back to addon `meta`.
    /// Recomputes the credit/watch derivations when it arrives, since they prefer TMDB data.
    var enrichment: Enrichment? { didSet { recomputeDerived() } }
    var related: [MetaPreview] = []
    /// In-app-playable trailers from the Trailerio addon (empty unless it's installed and has the
    /// title). Drives the hero's inline autoplay and the in-app Trailers row. Loaded after the base
    /// meta so it never blocks the image-first paint.
    var trailerCandidates: [TrailerCandidate] = []
    /// Per-episode TMDB info (runtime/still/overview/title), keyed by "season:episode". Filled lazily
    /// for the season currently in view (see `loadSeasonEnrichment`), merged over addon `Video` data.
    var episodeInfo: [String: EpisodeEnrichment] = [:]
    /// Seasons whose TMDB enrichment has already been merged, so revisiting a season (its `.task(id:)`
    /// re-firing as you scroll across it) doesn't re-merge identical data and needlessly re-render the
    /// whole episode strip.
    private var loadedSeasons: Set<Int> = []
    var seasonPosters: [Int: URL] = [:]
    private(set) var status: LoadStatus = .loading

    // MARK: - Cached episode derivations (recomputed only when `meta` changes)

    /// Every episode from every season in one continuous list, ordered by season then episode — the
    /// single horizontal strip Apple's TV app shows. The season selector is a "jump to" control.
    private(set) var sortedEpisodes: [Video] = []
    private(set) var seasons: [Int] = []
    /// First episode id of each season, for the season selector's "jump to" scroll.
    private(set) var seasonFirstEpisodeID: [Int: String] = [:]

    /// Cast & Crew row entries and the How-to-Watch provider cards. Each is read twice per detail render
    /// (an `.isEmpty` guard in the parent + the `ForEach` in the section) and rebuilds a fresh array of
    /// structs each time via `vm`, so they're cached here and recomputed only when `meta`/`enrichment`
    /// change — the same treatment as the episode derivations above.
    private(set) var creditEntries: [CreditEntry] = []
    private(set) var watchOptions: [WatchOption] = []

    /// Per-episode air-date display string, keyed by episode id. Cached because `airDate` parses an
    /// ISO-8601 date (allocating two `Date.ISO8601FormatStyle`s) — costly to run per card on every scroll.
    /// It depends only on the (static) episode list, so it's computed once when `meta` changes. Duration
    /// text is NOT cached here: it depends on the lazily-merged `episodeInfo`, and recomputing all episodes
    /// on each season merge is worse than formatting the ~6 visible cards on demand.
    private(set) var episodeAirDateText: [String: String] = [:]

    init(typeID: String, metaID: String, fallbackTitle: String, previewMeta: Meta? = nil) {
        self.typeID = typeID
        self.metaID = metaID
        self.fallbackTitle = fallbackTitle
        self.previewMeta = previewMeta
    }

    /// The pure presentation/formatting engine for the cheap derivations (display strings, credits,
    /// providers, hero facts, episode text). Rebuilt per access — cheap, since it only stores
    /// references. Heavy derivations are NOT read through here; use the cached properties above.
    var vm: MetaDetailViewModel {
        MetaDetailViewModel(
            meta: meta, enrichment: enrichment, related: related,
            typeID: typeID, metaID: metaID, fallbackTitle: fallbackTitle
        )
    }

    private func recomputeEpisodes() {
        let snapshot = vm
        let eps = snapshot.allEpisodes
        sortedEpisodes = eps
        seasons = snapshot.seasons
        var firsts: [Int: String] = [:]
        for ep in eps {
            guard let season = ep.season, firsts[season] == nil else { continue }
            firsts[season] = ep.id
        }
        seasonFirstEpisodeID = firsts

        // Air-date strings are a pure function of the (static) episode list, so parse them once here on
        // `meta` change rather than per card during scroll.
        var dates: [String: String] = [:]
        for episode in eps {
            if let date = snapshot.airDate(episode.released) { dates[episode.id] = date }
        }
        episodeAirDateText = dates
    }

    private func recomputeDerived() {
        let snapshot = vm
        creditEntries = snapshot.creditEntries
        watchOptions = snapshot.watchOptions
    }

    /// The hero's up-next episode (resume / next-to-watch). Pure algorithm in `MetaDetailViewModel`,
    /// run over the cached `sortedEpisodes`; the live Trakt watch state is injected by the caller.
    func upNext(
        progress: (Video) -> Double?,
        isWatched: (Video) -> Bool
    ) -> MetaDetailViewModel.UpNext? {
        vm.upNext(episodes: sortedEpisodes, progress: progress, isWatched: isWatched)
    }

    var currentSeasonDefault: Int? { seasons.first }

    func firstEpisodeID(of season: Int) -> String? { seasonFirstEpisodeID[season] }

    // MARK: - Loading

    func load() async {
        // Reset per-title TMDB state so a reused view never shows the previous title's enrichment or
        // episode data while the new title loads.
        enrichment = nil
        episodeInfo = [:]
        loadedSeasons = []
        seasonPosters = [:]
        trailerCandidates = []
        if let previewMeta {                       // sample/preview path — no networking
            meta = previewMeta
            status = .loaded
            return
        }
        status = .loading
        for addon in AddonRegistry.shared.enabledAddons {
            do {
                let response = try await StremioClient.shared.meta(
                    baseURL: addon.baseURL,
                    type: typeID,
                    id: metaID
                )
                meta = response.meta
                status = .loaded
                // Related (genre catalog) and TMDB enrichment run concurrently; neither blocks the
                // already-displayed base meta. Enrichment is best-effort — `enrich` returns nil when
                // TMDB isn't configured, the id isn't an IMDB id, or there's no match.
                async let relatedTask: Void = loadRelated()
                async let trailerTask = TrailerSource.candidates(type: typeID, id: metaID)
                async let enrichTask = TMDBService.shared.enrich(stremioType: typeID, imdbID: metaID)
                // Assign trailers first so autoplay starts as soon as they resolve — don't gate it
                // behind the (often slower) related-catalog fetch. All three still run concurrently.
                trailerCandidates = await trailerTask
                _ = await relatedTask
                enrichment = await enrichTask
                return
            } catch {
                continue
            }
        }
        status = .failed
    }

    private func loadRelated() async {
        guard let m = meta else { return }
        let firstGenre = m.genres?.first
        for addon in AddonRegistry.shared.enabledAddons {
            let catalogs = addon.manifest.catalogs ?? []
            guard let catalog = catalogs.first(where: { $0.type == typeID }) else { continue }
            let extra = firstGenre.map { ["genre": $0] } ?? [:]
            do {
                let response = try await StremioClient.shared.catalog(
                    baseURL: addon.baseURL,
                    type: typeID,
                    id: catalog.id,
                    extra: extra
                )
                let filtered = response.metas.filter { $0.id != metaID }
                related = Array(filtered.prefix(12))
                if !related.isEmpty { return }
            } catch {
                continue
            }
        }
    }

    /// Fetch and merge TMDB per-episode info + the season poster for one season. No-op when TMDB
    /// isn't configured or the season is nil / not yet known.
    func loadSeasonEnrichment(_ season: Int?) async {
        guard let season, !loadedSeasons.contains(season), TMDBService.shared.isConfigured else { return }
        guard let result = await TMDBService.shared.seasonEnrichment(imdbID: metaID, season: season) else { return }
        // Mark loaded even if empty, so scrolling back across this season doesn't re-fetch/re-merge and
        // re-render the whole strip. Only assign the observed dictionaries when there's something to add.
        loadedSeasons.insert(season)
        if !result.episodes.isEmpty {
            episodeInfo.merge(result.episodes) { _, new in new }
        }
        if let poster = result.posterURL { seasonPosters[season] = poster }
    }

    func recordHistory() {
        WatchHistory.shared.record(
            typeID: typeID,
            metaID: metaID,
            name: meta?.name ?? fallbackTitle,
            poster: meta?.poster,
            background: meta?.background,
            logo: meta?.logo
        )
    }
}
