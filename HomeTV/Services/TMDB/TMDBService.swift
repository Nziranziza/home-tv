import Foundation

/// App-facing TMDB enrichment source. Resolves an addon `Meta` (by IMDB id) to a view-ready
/// `Enrichment`, delegating all networking to the `TMDBClient` actor and caching results in memory.
///
/// An `actor` (not `@MainActor`): it publishes nothing observed — views only `await` its async methods —
/// so its resolution/mapping work (credit sorts, provider grouping, filmography `Dictionary(grouping:)`,
/// URL building) runs off the main actor instead of stalling the UI. Its return types are all `Sendable`.
///
/// Enrichment is best-effort and additive: any failure returns whatever was gathered (or `nil`), and
/// the view falls back to addon data. It is a no-op when `TMDBConfig.isConfigured == false`.
actor TMDBService {
    static let shared = TMDBService()

    private let client = TMDBClient.shared

    /// Full enrichment keyed by "{tmdbType}:{imdbID}".
    private var enrichmentCache: [String: Enrichment] = [:]
    /// IMDB id → resolved TMDB (id, mediaType), so season/discovery calls skip the find round-trip.
    private var resolutionCache: [String: TMDBResolution] = [:]
    /// Per-season episode info + poster, keyed by "{tvID}:{season}".
    private var seasonCache: [String: SeasonEnrichment] = [:]
    /// Person bio + grouped filmography, keyed by TMDB person id (drives the cast/crew screen).
    private var personCache: [Int: PersonProfile] = [:]
    /// People matching a search term, keyed by the lowercased query (drives Search's Cast & Crew row).
    private var personSearchCache: [String: [CastPerson]] = [:]
    /// The In Theaters & At Home row, keyed by the calendar day it was built for — the release windows
    /// it slices by only move once a day, so one fetch per day per launch is plenty.
    private var theatricalCache: [String: [TheatricalItem]] = [:]

    /// How many people the Cast & Crew row holds — enough to scroll, not enough to pull a long tail of
    /// near-irrelevant matches.
    private static let personSearchLimit = 20

    // In-flight coalescing: the hero provider badge and the detail screen (and repeated `.task(id:)`
    // fires) request the same enrichment concurrently — without this both miss the cache and each runs
    // the full multi-request TMDB fetch + decode. These collapse simultaneous identical requests onto one.
    private var enrichInFlight: [String: Task<Enrichment?, Never>] = [:]
    private var resolveInFlight: [String: Task<TMDBResolution?, Never>] = [:]
    private var seasonInFlight: [String: Task<SeasonEnrichment?, Never>] = [:]
    private var personInFlight: [Int: Task<PersonProfile?, Never>] = [:]
    private var personSearchInFlight: [String: Task<[CastPerson], Never>] = [:]
    private var theatricalInFlight: [String: Task<[TheatricalItem]?, Never>] = [:]

    private struct TMDBResolution: Sendable { let id: Int; let mediaType: String }
    struct SeasonEnrichment: Sendable { var episodes: [String: EpisodeEnrichment]; var posterURL: URL? }

    /// `nonisolated` — it only reads a static config flag (no actor state), so callers can check it
    /// synchronously without hopping onto the actor.
    nonisolated var isConfigured: Bool { TMDBConfig.isConfigured }

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
        if let inFlight = enrichInFlight[cacheKey] { return await inFlight.value }

        let task = Task { () -> Enrichment? in
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
        enrichInFlight[cacheKey] = task
        let result = await task.value
        enrichInFlight[cacheKey] = nil
        return result
    }

    /// Per-season episode metadata + poster, fetched lazily for the selected season (Stage C wiring).
    func seasonEnrichment(imdbID: String, season: Int) async -> SeasonEnrichment? {
        guard isConfigured, imdbID.hasPrefix("tt"),
              let resolution = await resolve(imdbID: imdbID, mediaType: "tv") else { return nil }

        let key = "\(resolution.id):\(season)"
        if let cached = seasonCache[key] { return cached }
        if let inFlight = seasonInFlight[key] { return await inFlight.value }

        let task = Task { () -> SeasonEnrichment? in
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
        seasonInFlight[key] = task
        let result = await task.value
        seasonInFlight[key] = nil
        return result
    }

    // MARK: - In Theaters & At Home

    /// The In Theaters & At Home row's source: what is in cinemas right now, then what has reached
    /// buy-or-rent at home, newest first.
    ///
    /// TMDB sources this row rather than merely enriching it because nothing else can — an addon
    /// catalog is an ordered list of titles with no release-window data at all, and Cinemeta dates a
    /// title only to the year. Everything *after* a selection still belongs to the addons: the cards
    /// carry `TMDBRef`-encoded ids that `imdbID(for:)` bridges on select, so the detail screen and its
    /// streams load from Cinemeta exactly as they do for every other row.
    ///
    /// Three discover calls, run concurrently, and none of them per-item. They differ only in which
    /// release types and which date window they ask for — that pair is what assigns each card its
    /// availability, since a TMDB list item carries no such field of its own.
    ///
    /// Returns `nil` when every window failed, which is a network problem rather than an empty row, so
    /// the caller can retry instead of hiding the row for the rest of the day.
    func theatricalItems() async -> [TheatricalItem]? {
        guard isConfigured else { return [] }

        let key = TMDBConfig.day(.now)
        if let cached = theatricalCache[key] { return cached }
        if let inFlight = theatricalInFlight[key] { return await inFlight.value }

        let task = Task { () -> [TheatricalItem]? in
            let now = Date.now
            let region = TMDBConfig.region
            // The two at-home windows meet at this edge, so it is computed once and shared: the newer
            // window ends where the older one begins, with no day falling into both or neither.
            let newlyAvailableEdge = TMDBConfig.date(Self.newlyAvailableDays, daysBefore: now)

            async let landed = client.moviesReleased(
                region: region,
                releaseTypes: Self.digitalReleaseTypes,
                from: newlyAvailableEdge,
                to: now,
                minimumVotes: Self.minimumVotes,
                monetizationTypes: Self.buyOrRentMonetization
            )
            async let established = client.moviesReleased(
                region: region,
                releaseTypes: Self.digitalReleaseTypes,
                from: TMDBConfig.date(Self.buyOrRentDays, daysBefore: now),
                to: newlyAvailableEdge,
                minimumVotes: Self.minimumVotes,
                monetizationTypes: Self.buyOrRentMonetization
            )
            async let theaters = client.moviesReleased(
                region: region,
                releaseTypes: Self.theatricalReleaseTypes,
                from: TMDBConfig.date(Self.theatricalDays, daysBefore: now),
                to: now,
                minimumVotes: Self.minimumVotes
            )

            // Each window degrades on its own: a failed call costs its slice of the row, not the row.
            let landedPage = try? await landed
            let establishedPage = try? await established
            let theatersPage = try? await theaters
            guard landedPage != nil || establishedPage != nil || theatersPage != nil else { return nil }

            let items = Self.theatricalItems(
                landed: landedPage?.results ?? [],
                established: establishedPage?.results ?? [],
                theaters: theatersPage?.results ?? []
            )

            // Hold for the day only when every window answered. Caching a row that is missing its
            // theatrical half because one call blipped would keep it missing until tomorrow.
            let isComplete = landedPage != nil && establishedPage != nil && theatersPage != nil
            // Nothing to show *and* a window still unheard from is indistinguishable from total
            // failure, so report it as one rather than letting the row hide itself on a half answer.
            guard isComplete || !items.isEmpty else { return nil }

            if isComplete, !items.isEmpty { theatricalCache[key] = items }
            return items
        }
        theatricalInFlight[key] = task
        let result = await task.value
        theatricalInFlight[key] = nil
        return result
    }

    /// Merge the three windows into one row, in the order the row shows them.
    ///
    /// Cinemas lead, for two reasons. It is what the row is named for and the half you cannot get from
    /// any other row in the app — and a title is claimed by the first window it appears in, so putting
    /// theatrical first also means a film still playing reads as in cinemas rather than being counted
    /// against the at-home half by a digital release it happens to have picked up.
    private static func theatricalItems(
        landed: [TMDBMovieListItem],
        established: [TMDBMovieListItem],
        theaters: [TMDBMovieListItem]
    ) -> [TheatricalItem] {
        var claimed = Set<Int>()
        let windows: [[TheatricalItem]] = [
            (theaters, TheatricalAvailability.inTheaters),
            (landed, .newlyAvailable),
            (established, .buyOrRent)
        ].map { window in
            window.0.compactMap { result in
                guard claimed.insert(result.id).inserted else { return nil }
                return theatricalItem(from: result, availability: window.1)
            }
        }

        // A share of the row per window before any of them takes a second helping, then the leftovers
        // in the same order. Each window returns a full page, so without this whichever window leads
        // fills the row on its own and the other two never reach it — in a row named for both halves.
        var items = windows.flatMap { $0.prefix(theatricalWindowShare) }
        items += windows.flatMap { $0.dropFirst(theatricalWindowShare) }
        return Array(items.prefix(theatricalLimit))
    }

    /// Map one list entry to a card. Artwork is required — the row is nothing but key art, so an
    /// art-less title is dropped rather than shown as an empty block.
    private static func theatricalItem(
        from result: TMDBMovieListItem,
        availability: TheatricalAvailability
    ) -> TheatricalItem? {
        guard let poster = TMDBConfig.imageURL(path: result.posterPath, size: .w780)?.absoluteString,
              let title = result.title?.nilIfBlank else { return nil }

        let preview = MetaPreview(
            id: TMDBRef(mediaType: "movie", id: result.id).encoded,
            type: "movie",
            name: title,
            poster: poster,
            posterShape: nil,
            background: TMDBConfig.imageURL(path: result.backdropPath, size: .w1280)?.absoluteString,
            logo: nil,
            description: result.overview?.nilIfBlank,
            releaseInfo: year(from: result.releaseDate),
            imdbRating: nil,
            genres: (result.genreIds ?? []).compactMap { TMDBGenres.name(forMovie: $0) }
        )
        return TheatricalItem(preview: preview, availability: availability)
    }

    // MARK: - Person (cast/crew screen)

    /// Resolve a TMDB person to their bio + grouped filmography. Cached per id. Returns nil when TMDB
    /// isn't configured or the person can't be fetched, so the cast screen can degrade gracefully.
    func personProfile(id: Int) async -> PersonProfile? {
        guard isConfigured else { return nil }
        if let cached = personCache[id] { return cached }
        if let inFlight = personInFlight[id] { return await inFlight.value }

        let task = Task { () -> PersonProfile? in
            guard let detail = try? await client.person(id: id) else { return nil }
            let profile = Self.makeProfile(from: detail)
            personCache[id] = profile
            return profile
        }
        personInFlight[id] = task
        let result = await task.value
        personInFlight[id] = nil
        return result
    }

    /// People matching a free-text query, as `CastPerson` values ready for the Cast & Crew row on the
    /// Search screen. Cached (and coalesced) per lowercased query, so retyping a term costs nothing.
    /// Returns an empty list when TMDB isn't configured or the request fails, so Search degrades to its
    /// catalog sections rather than erroring.
    func searchPeople(query: String) async -> [CastPerson] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard isConfigured, trimmed.count >= 2 else { return [] }

        let key = trimmed.lowercased()
        if let cached = personSearchCache[key] { return cached }
        if let inFlight = personSearchInFlight[key] { return await inFlight.value }

        let task = Task { () -> [CastPerson] in
            guard let response = try? await client.searchPeople(query: trimmed) else { return [] }
            let people = Self.makePeople(from: response.results)
            personSearchCache[key] = people
            return people
        }
        personSearchInFlight[key] = task
        let result = await task.value
        personSearchInFlight[key] = nil
        return result
    }

    /// Drop unnamed entries, order by TMDB popularity, and cap the row.
    private static func makePeople(from results: [TMDBPersonSearchResult]) -> [CastPerson] {
        results
            .compactMap { result -> (person: CastPerson, popularity: Double)? in
                guard let name = result.name, !name.isEmpty else { return nil }
                let person = CastPerson(
                    id: result.id,
                    name: name,
                    profileURL: TMDBConfig.imageURL(path: result.profilePath, size: .w500)
                )
                return (person, result.popularity ?? 0)
            }
            .sorted { $0.popularity > $1.popularity }
            .prefix(personSearchLimit)
            .map(\.person)
    }

    /// Map a raw person detail into the view-facing profile: the header fields plus the filmography
    /// rows, grouped to mirror Apple's person page — Movies (film roles), one row per crew job
    /// (Producer, Director, …) ordered by how many credits it has, then TV guest appearances.
    private static func makeProfile(from detail: TMDBPersonDetail) -> PersonProfile {
        let cast = detail.combinedCredits?.cast ?? []
        let crew = detail.combinedCredits?.crew ?? []
        var sections: [FilmographySection] = []

        // Movies — film cast roles, poster cards.
        if let movies = section(title: "Movies", style: .poster,
                                 from: cast.filter { ($0.mediaType ?? "movie") == "movie" },
                                 role: { $0.character }) {
            sections.append(movies)
        }

        // Crew work — grouped by job, ordered by credit count (Producer first for a film producer),
        // dropping one-off jobs so the page stays the handful of meaningful rows Apple shows.
        let byJob = Dictionary(grouping: crew) { $0.job ?? "Crew" }
            .filter { $0.value.count >= crewJobMinimum }
            .sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }
        for (job, list) in byJob {
            if let s = section(title: job, style: .poster, from: list, role: { _ in nil }) {
                sections.append(s)
            }
        }

        // Guest Appearances — TV cast roles, landscape cards with a caption.
        if let guests = section(title: "Guest Appearances", style: .landscape,
                                from: cast.filter { $0.mediaType == "tv" },
                                role: { $0.character }) {
            sections.append(guests)
        }

        return PersonProfile(
            id: detail.id,
            name: detail.name ?? "",
            biography: detail.biography?.nilIfBlank,
            profileURL: TMDBConfig.imageURL(path: detail.profilePath, size: .w500),
            sections: sections
        )
    }

    /// Build one filmography section: de-duplicate by title, sort by popularity, drop art-less items,
    /// and cap the count. Returns nil when nothing survives.
    private static func section(
        title: String, style: FilmographySection.Style,
        from credits: [TMDBPersonCredit], role: (TMDBPersonCredit) -> String?
    ) -> FilmographySection? {
        var seen = Set<Int>()
        let items = credits
            .sorted { ($0.popularity ?? 0, $0.voteCount ?? 0) > ($1.popularity ?? 0, $1.voteCount ?? 0) }
            .compactMap { credit -> FilmographyItem? in
                guard seen.insert(credit.id).inserted else { return nil }
                return item(from: credit, style: style, role: role(credit))
            }
            .prefix(filmographySectionLimit)
        guard !items.isEmpty else { return nil }
        return FilmographySection(title: title, style: style, items: Array(items))
    }

    /// Map one credit to a display item, encoding a `TMDBRef` id so selecting it resolves to an IMDB
    /// id on demand (same bridge as the Related row). Poster rows require a poster; landscape rows
    /// prefer a backdrop and fall back to the poster. Art-less credits are dropped.
    private static func item(
        from credit: TMDBPersonCredit, style: FilmographySection.Style, role: String?
    ) -> FilmographyItem? {
        let mediaType = credit.mediaType ?? "movie"
        let name = credit.title ?? credit.name ?? ""
        guard !name.isEmpty else { return nil }

        let posterURL = TMDBConfig.imageURL(path: credit.posterPath, size: .w500)
        let backdropURL = TMDBConfig.imageURL(path: credit.backdropPath, size: .w780)
        let primaryArt = style == .poster ? posterURL : (backdropURL ?? posterURL)
        guard primaryArt != nil else { return nil }

        let year = Self.year(from: credit.releaseDate ?? credit.firstAirDate)
        let preview = MetaPreview(
            id: TMDBRef(mediaType: mediaType, id: credit.id).encoded,
            type: mediaType == "tv" ? "series" : "movie",
            name: name,
            poster: posterURL?.absoluteString,
            posterShape: nil,
            background: backdropURL?.absoluteString,
            logo: nil,
            description: credit.overview?.nilIfBlank,
            releaseInfo: year,
            imdbRating: nil,
            genres: TMDBGenres.primaryName(ids: credit.genreIds, mediaType: mediaType).map { [$0] }
        )
        return FilmographyItem(preview: preview, role: role?.nilIfBlank)
    }

    // MARK: - Resolution (IMDB → TMDB id)

    private func resolve(imdbID: String, mediaType: String) async -> TMDBResolution? {
        // Key by both id and media type: a resolution is type-specific (movie vs tv pick different
        // results), so the cached entry must not be reused across types for the same id.
        let cacheKey = "\(imdbID)::\(mediaType)"
        if let cached = resolutionCache[cacheKey] { return cached }
        if let inFlight = resolveInFlight[cacheKey] { return await inFlight.value }

        let task = Task { () -> TMDBResolution? in
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
        resolveInFlight[cacheKey] = task
        let result = await task.value
        resolveInFlight[cacheKey] = nil
        return result
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
        e.year = Self.year(from: detail.releaseDate)
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
        e.year = Self.year(from: detail.firstAirDate)
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

    /// Four-digit release year from a TMDB date string ("2026-05-29" → "2026"). nil when absent/malformed.
    private static func year(from date: String?) -> String? {
        guard let date, date.count >= 4 else { return nil }
        return String(date.prefix(4))
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
        // Rank, then TMDB's own order as the tie-break. Swift's sort isn't stable, so equal-rank videos
        // are ordered by their original index rather than left to the sort's discretion.
        return results
            .filter { $0.site == "YouTube" && ($0.type == "Trailer" || $0.type == "Teaser") }
            .enumerated()
            .sorted { lhs, rhs in
                let left = Self.trailerRank(lhs.element)
                let right = Self.trailerRank(rhs.element)
                return left == right ? lhs.offset < rhs.offset : left < right
            }
            .compactMap { _, video in
                guard let key = video.key, !key.isEmpty else { return nil }
                return Trailer(id: key, title: video.name ?? "Trailer")
            }
    }

    /// Sort key for a trailer video — lower comes first. Official beats unofficial (the primary axis, so
    /// the studio cut leads the row), and within each of those a full Trailer beats a Teaser.
    private static func trailerRank(_ video: TMDBVideo) -> Int {
        let officialRank = (video.official ?? false) ? 0 : 2
        let typeRank = video.type == "Teaser" ? 1 : 0
        return officialRank + typeRank
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

    /// Cap on the In Theaters & At Home row. The cards are showcase-sized (about three across), so a
    /// longer run is a lot of scrolling for a row that is meant to answer "what is new right now".
    private static let theatricalLimit = 12

    /// Slots each release window is guaranteed before any window takes a second helping.
    private static let theatricalWindowShare = 4

    /// TMDB release types 4 (digital) and 5 (physical) — between them, "you can buy or rent it" — and
    /// 2 (limited) and 3 (wide), which together mean "it is in cinemas".
    private static let digitalReleaseTypes = "4|5"
    private static let theatricalReleaseTypes = "2|3"

    /// A digital release type only says a title was *published* digitally — a subscription-only
    /// premiere has one and nothing to buy. This asks JustWatch whether you can actually rent or buy it
    /// in the region, so the at-home windows can only contain titles the bag glyph is true of.
    private static let buyOrRentMonetization = "rent|buy"

    /// Ratings a title needs before it can reach the row. Popularity alone does not separate a wide
    /// release from a regional title nobody has seen — both can top a `popularity.desc` page — so the
    /// vote count is what does. Low enough that a film released days ago still clears it.
    private static let minimumVotes = 20

    /// How recent a digital release has to be to read as *just* landed, how far back the row reaches
    /// for buy-or-rent titles at all, and how long after opening a film still counts as in cinemas.
    /// Counted in calendar days on `TMDBConfig.releaseCalendar`, like the dates they are compared to.
    private static let newlyAvailableDays = 14
    private static let buyOrRentDays = 60
    private static let theatricalDays = 45

    /// Cap per filmography row, and the minimum credits a crew job needs to earn its own row (so a
    /// one-off "Thanks" credit doesn't become a section).
    private static let filmographySectionLimit = 20
    private static let crewJobMinimum = 2

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
