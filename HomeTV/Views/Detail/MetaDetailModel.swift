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

    /// Base meta from the addon. Recomputes the cached episode derivations when it changes.
    var meta: Meta? { didSet { recomputeEpisodes() } }
    /// TMDB enrichment sidecar, populated after the base meta loads. nil until then (or when TMDB
    /// isn't configured / the id isn't an IMDB id) — every consumer falls back to addon `meta`.
    var enrichment: Enrichment?
    var related: [MetaPreview] = []
    /// Per-episode TMDB info (runtime/still/overview/title), keyed by "season:episode". Filled lazily
    /// for the season currently in view (see `loadSeasonEnrichment`), merged over addon `Video` data.
    var episodeInfo: [String: EpisodeEnrichment] = [:]
    var seasonPosters: [Int: URL] = [:]
    private(set) var status: LoadStatus = .loading

    // MARK: - Cached episode derivations (recomputed only when `meta` changes)

    /// Every episode from every season in one continuous list, ordered by season then episode — the
    /// single horizontal strip Apple's TV app shows. The season selector is a "jump to" control.
    private(set) var sortedEpisodes: [Video] = []
    private(set) var seasons: [Int] = []
    /// First episode id of each season, for the season selector's "jump to" scroll.
    private(set) var seasonFirstEpisodeID: [Int: String] = [:]

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
        seasonPosters = [:]
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
                async let enrichTask = TMDBService.shared.enrich(stremioType: typeID, imdbID: metaID)
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
        guard let season, TMDBService.shared.isConfigured else { return }
        guard let result = await TMDBService.shared.seasonEnrichment(imdbID: metaID, season: season) else { return }
        episodeInfo.merge(result.episodes) { _, new in new }
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
