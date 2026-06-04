import Foundation
import Observation

/// App-facing TMDB enrichment source. Mirrors the `@Observable @MainActor` singleton shape used by
/// `TraktService`/`AddonRegistry`. Resolves an addon `Meta` (by IMDB id) to a view-ready `Enrichment`,
/// delegating all networking to the `TMDBClient` actor and caching results in memory.
///
/// Enrichment is best-effort and additive: any failure returns whatever was gathered (or `nil`), and
/// the view falls back to addon data. It is a no-op when `TMDBConfig.isConfigured == false`.
@Observable
@MainActor
final class TMDBService {
    static let shared = TMDBService()

    @ObservationIgnored private let client = TMDBClient.shared

    /// Full enrichment keyed by "{tmdbType}:{imdbID}".
    @ObservationIgnored private var enrichmentCache: [String: Enrichment] = [:]
    /// IMDB id → resolved TMDB (id, mediaType), so season/discovery calls skip the find round-trip.
    @ObservationIgnored private var resolutionCache: [String: TMDBResolution] = [:]
    /// Per-season episode info + poster, keyed by "{tvID}:{season}".
    @ObservationIgnored private var seasonCache: [String: SeasonEnrichment] = [:]

    private struct TMDBResolution: Sendable { let id: Int; let mediaType: String }
    struct SeasonEnrichment: Sendable { var episodes: [String: EpisodeEnrichment]; var posterURL: URL? }

    var isConfigured: Bool { TMDBConfig.isConfigured }

    // MARK: - Top-level enrichment

    /// Resolve and merge TMDB metadata for an addon item. `stremioType` is the addon type
    /// ("movie"/"series"); only IMDB-keyed ids (`tt…`) are enriched. Returns `nil` when not
    /// configured, not an IMDB id, an unsupported type, or no TMDB match.
    func enrich(stremioType: String, imdbID: String) async -> Enrichment? {
        guard isConfigured, imdbID.hasPrefix("tt"), let mediaType = Self.tmdbType(for: stremioType) else {
            return nil
        }

        let cacheKey = "\(mediaType):\(imdbID)"
        if let cached = enrichmentCache[cacheKey] { return cached }

        guard let resolution = await resolve(imdbID: imdbID, mediaType: mediaType) else { return nil }

        let enrichment: Enrichment?
        switch resolution.mediaType {
        case "movie": enrichment = await enrichMovie(id: resolution.id)
        case "tv": enrichment = await enrichTV(id: resolution.id)
        default: enrichment = nil
        }

        if let enrichment { enrichmentCache[cacheKey] = enrichment }
        return enrichment
    }

    /// Per-season episode metadata + poster, fetched lazily for the selected season (Stage C wiring).
    func seasonEnrichment(imdbID: String, season: Int) async -> SeasonEnrichment? {
        guard isConfigured, imdbID.hasPrefix("tt"),
              let resolution = await resolve(imdbID: imdbID, mediaType: "tv") else { return nil }

        let key = "\(resolution.id):\(season)"
        if let cached = seasonCache[key] { return cached }

        guard let detail = try? await client.season(tvID: resolution.id, season: season) else { return nil }

        var episodes: [String: EpisodeEnrichment] = [:]
        for ep in detail.episodes {
            guard let number = ep.episodeNumber else { continue }
            episodes[Enrichment.episodeKey(season: season, episode: number)] = EpisodeEnrichment(
                title: ep.name,
                overview: ep.overview,
                stillURL: TMDBConfig.imageURL(path: ep.stillPath, size: .w780),
                runtimeMinutes: ep.runtime
            )
        }
        let result = SeasonEnrichment(
            episodes: episodes,
            posterURL: TMDBConfig.imageURL(path: detail.posterPath, size: .w500)
        )
        seasonCache[key] = result
        return result
    }

    // MARK: - Resolution (IMDB → TMDB id)

    private func resolve(imdbID: String, mediaType: String) async -> TMDBResolution? {
        // Key by both id and media type: a resolution is type-specific (movie vs tv pick different
        // results), so the cached entry must not be reused across types for the same id.
        let cacheKey = "\(imdbID)::\(mediaType)"
        if let cached = resolutionCache[cacheKey] { return cached }
        guard let result = try? await client.find(imdbID: imdbID) else { return nil }

        let id: Int?
        switch mediaType {
        case "movie": id = result.movieResults.first?.id
        case "tv": id = result.tvResults.first?.id
        default: id = result.movieResults.first?.id ?? result.tvResults.first?.id
        }
        guard let id else { return nil }

        let resolution = TMDBResolution(id: id, mediaType: mediaType)
        resolutionCache[cacheKey] = resolution
        return resolution
    }

    // MARK: - Movie / TV mapping

    private func enrichMovie(id: Int) async -> Enrichment? {
        // Detail + watch providers fetched concurrently (providers are a separate endpoint).
        async let detailReq = client.movie(id: id)
        async let providersReq = client.watchProviders(mediaType: "movie", id: id)
        guard let detail = try? await detailReq else { return nil }
        let providers = try? await providersReq

        var e = Enrichment()
        e.logoURL = preferredLogoURL(detail.images)
        e.backdropURL = backdropURL(path: detail.backdropPath, images: detail.images)
        e.overview = detail.overview?.nilIfBlank
        e.genres = detail.genres?.map(\.name)
        e.rating = detail.voteAverage
        e.runtimeMinutes = detail.runtime
        e.status = detail.status?.nilIfBlank
        e.country = detail.productionCountries?.first?.name
        e.language = detail.spokenLanguages?.first?.englishName
        e.certification = movieCertification(detail.releaseDates)
        applyCredits(detail.credits, to: &e)
        applyWatchProviders(providers, to: &e)
        e.trailers = trailers(from: detail.videos)
        e.recommendations = Self.recommendationPreviews(detail.recommendations, fallbackType: "movie")
        return e
    }

    private func enrichTV(id: Int) async -> Enrichment? {
        async let detailReq = client.tv(id: id)
        async let providersReq = client.watchProviders(mediaType: "tv", id: id)
        guard let detail = try? await detailReq else { return nil }
        let providers = try? await providersReq

        var e = Enrichment()
        e.logoURL = preferredLogoURL(detail.images)
        e.backdropURL = backdropURL(path: detail.backdropPath, images: detail.images)
        e.overview = detail.overview?.nilIfBlank
        e.genres = detail.genres?.map(\.name)
        e.rating = detail.voteAverage
        e.runtimeMinutes = detail.episodeRunTime?.first
        e.status = detail.status?.nilIfBlank
        e.country = detail.productionCountries?.first?.name
        e.language = detail.spokenLanguages?.first?.englishName
        e.certification = tvCertification(detail.contentRatings)
        applyCredits(detail.credits, to: &e)
        applyWatchProviders(providers, to: &e)
        if let badge = tvBadgeURL(detail: detail, providers: providers) { e.providerBadgeURL = badge }
        e.trailers = trailers(from: detail.videos)
        e.recommendations = Self.recommendationPreviews(detail.recommendations, fallbackType: "tv")
        return e
    }

    // MARK: - Field helpers

    private func preferredLogoURL(_ images: TMDBImageList?) -> URL? {
        guard let logos = images?.logos, !logos.isEmpty else { return nil }
        // Prefer an English (or textless) logo, otherwise the highest-voted available.
        let chosen = logos.first { $0.code == "en" }
            ?? logos.first { $0.code == nil }
            ?? logos.max { ($0.voteAverage ?? 0) < ($1.voteAverage ?? 0) }
        return TMDBConfig.imageURL(path: chosen?.filePath, size: .w500)
    }

    private func backdropURL(path: String?, images: TMDBImageList?) -> URL? {
        if let url = TMDBConfig.imageURL(path: path, size: .w1280) { return url }
        return TMDBConfig.imageURL(path: images?.backdrops?.first?.filePath, size: .w1280)
    }

    /// TV hero badge URL. Apple shows the originating *network* (e.g. "MGM+ Original"), but TMDB's
    /// network logos are wide wordmarks ("NETFLIX") that look tiny in the square badge slot. So we use
    /// the network only to pick the right *brand*, then render that brand's square watch-provider icon
    /// (e.g. the red "N"). This also sidesteps the watch-provider ranking putting an aggregator like
    /// fuboTV first. Falls back to the network's own logo when no matching provider icon exists.
    private func tvBadgeURL(detail: TMDBTVDetail, providers: TMDBWatchProviders?) -> URL? {
        guard let network = detail.networks?.last else { return nil }
        let key = Self.brandKey(network.name)

        if !key.isEmpty, let country = providers?.results[Self.providerRegion] {
            let all = [country.flatrate, country.free, country.ads, country.rent, country.buy]
                .compactMap { $0 }.flatMap { $0 }
            let matches = all.filter { provider in
                let candidate = Self.brandKey(provider.providerName)
                return candidate.contains(key) || key.contains(candidate)
            }
            // Shortest name ≈ the brand's own app (e.g. "MGM Plus" over "MGM+ Amazon Channel").
            if let best = matches.min(by: { $0.providerName.count < $1.providerName.count }) {
                return TMDBConfig.imageURL(path: best.logoPath, size: .w185)
            }
        }
        return TMDBConfig.imageURL(path: network.logoPath, size: .w185)
    }

    /// Normalize a brand name for loose matching: lowercase, letters/numbers only ("MGM+" → "mgm").
    private static func brandKey(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Map US watch-provider availability into the hero badge (primary subscription provider) and the
    /// "How to Watch" groups. Like Apple TV+, the badge shows only when the title streams on a
    /// subscription service; rent/buy-only titles get no badge but still list under How to Watch.
    private func applyWatchProviders(_ providers: TMDBWatchProviders?, to e: inout Enrichment) {
        guard let country = providers?.results[Self.providerRegion] else { return }

        func provider(_ p: TMDBProvider) -> WatchProvider {
            WatchProvider(id: p.providerId, name: p.providerName,
                          logoURL: TMDBConfig.imageURL(path: p.logoPath, size: .w185))
        }
        func group(_ list: [TMDBProvider]?, _ label: String) -> WatchProviderGroup? {
            guard let list, !list.isEmpty else { return nil }
            let sorted = list.sorted { ($0.displayPriority ?? .max) < ($1.displayPriority ?? .max) }
            return WatchProviderGroup(label: label, providers: sorted.map(provider))
        }

        e.watchProviderGroups = [
            group(country.flatrate, "Stream"),
            group(country.free, "Free"),
            group(country.ads, "Free with Ads"),
            group(country.rent, "Rent"),
            group(country.buy, "Buy")
        ].compactMap { $0 }
        e.watchLink = country.link.flatMap(URL.init(string:))

        // Hero badge: highest-priority subscription (flatrate) provider only.
        e.providerBadgeURL = country.flatrate?
            .min { ($0.displayPriority ?? .max) < ($1.displayPriority ?? .max) }
            .flatMap { TMDBConfig.imageURL(path: $0.logoPath, size: .w185) }
    }

    private func applyCredits(_ credits: TMDBCredits?, to e: inout Enrichment) {
        guard let credits else { return }
        e.cast = credits.cast
            .sorted { ($0.order ?? .max) < ($1.order ?? .max) }
            .map { EnrichedCastMember(
                id: $0.id,
                name: $0.name,
                character: $0.character?.nilIfBlank,
                profileURL: TMDBConfig.imageURL(path: $0.profilePath, size: .w185)
            ) }
        e.directors = credits.crew.filter { $0.job == "Director" }.map(\.name).uniqued()
        let writingJobs: Set<String> = ["Writer", "Screenplay", "Story", "Author"]
        e.writers = credits.crew
            .filter { $0.department == "Writing" || ($0.job.map(writingJobs.contains) ?? false) }
            .map(\.name).uniqued()
    }

    private func movieCertification(_ releaseDates: TMDBReleaseDatesResponse?) -> String? {
        guard let us = releaseDates?.results.first(where: { $0.code == "US" }) else { return nil }
        return us.releaseDates.compactMap { $0.certification?.nilIfBlank }.first
    }

    private func tvCertification(_ ratings: TMDBContentRatingsResponse?) -> String? {
        ratings?.results.first { $0.code == "US" }?.rating?.nilIfBlank
    }

    private func trailers(from videos: TMDBVideoList?) -> [Trailer] {
        guard let results = videos?.results else { return [] }
        return results
            .filter { $0.site == "YouTube" && ($0.type == "Trailer" || $0.type == "Teaser") }
            .sorted { ($0.official ?? false) && !($1.official ?? false) }
            .compactMap { video in
                guard let key = video.key, !key.isEmpty else { return nil }
                return Trailer(id: key, title: video.name ?? "Trailer")
            }
    }

    // MARK: - Discovery ("More Like This")

    /// Map TMDB `recommendations` (which arrive *free* in the detail response's `append_to_response`)
    /// to display previews — no extra network here. The id encodes the TMDB ref (`tmdb:movie:550`)
    /// because TMDB items have no IMDB id; navigation resolves it lazily via `imdbID(for:)` on select.
    private static func recommendationPreviews(_ recs: TMDBRecommendations?, fallbackType: String) -> [MetaPreview] {
        guard let items = recs?.results else { return [] }
        return items.prefix(recommendationLimit).compactMap { item in
            let mediaType = item.mediaType ?? fallbackType
            // A poster is required — the Related row is poster-shaped; skip art-less items.
            guard let poster = TMDBConfig.imageURL(path: item.posterPath, size: .w500)?.absoluteString else {
                return nil
            }
            return MetaPreview(
                id: TMDBRef(mediaType: mediaType, id: item.id).encoded,
                type: mediaType == "tv" ? "series" : "movie",
                name: item.title ?? item.name ?? "",
                poster: poster,
                posterShape: nil,
                background: TMDBConfig.imageURL(path: item.backdropPath, size: .w1280)?.absoluteString,
                logo: nil,
                description: nil,
                releaseInfo: nil,
                imdbRating: nil,
                genres: nil
            )
        }
    }

    /// Resolve a TMDB recommendation ref to its IMDB id so the addon-backed detail screen can load it.
    /// One `external_ids` call, made only when the user actually selects a "More Like This" title.
    func imdbID(for ref: TMDBRef) async -> String? {
        guard let externals = try? await client.externalIDs(mediaType: ref.mediaType, id: ref.id),
              let imdb = externals.imdbId, !imdb.isEmpty else { return nil }
        return imdb
    }

    // MARK: - Statics

    private static let recommendationLimit = 12

    /// Region for watch-provider availability (providers differ per country). Tied to the en-US locale.
    private static let providerRegion = "US"

    /// Map an addon Stremio type to the TMDB media type. Returns nil for unsupported types.
    private static func tmdbType(for stremioType: String) -> String? {
        switch stremioType {
        case "movie": "movie"
        case "series": "tv"
        default: nil
        }
    }
}

/// A reference to a TMDB title (media type + id), encoded into a `MetaPreview.id` as `tmdb:movie:550`
/// so "More Like This" items can ride through the existing Related row and be resolved to an IMDB id
/// only when selected (TMDB recommendation items carry no IMDB id of their own).
struct TMDBRef: Sendable, Hashable {
    let mediaType: String   // "movie" | "tv"
    let id: Int

    var encoded: String { "tmdb:\(mediaType):\(id)" }

    init(mediaType: String, id: Int) {
        self.mediaType = mediaType
        self.id = id
    }

    /// Parse back from an encoded `MetaPreview.id`; nil for ordinary IMDB ids (`tt…`).
    init?(encodedID: String) {
        let parts = encodedID.split(separator: ":")
        guard parts.count == 3, parts[0] == "tmdb", let id = Int(parts[2]) else { return nil }
        self.mediaType = String(parts[1])
        self.id = id
    }
}

private extension String {
    /// nil when the string is empty or only whitespace; otherwise self.
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : self
    }
}

private extension Array where Element: Hashable {
    /// Stable de-duplication preserving first-seen order.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
