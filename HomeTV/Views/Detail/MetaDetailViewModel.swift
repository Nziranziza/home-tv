import Foundation

/// Pure, dependency-free presentation logic for `MetaDetailView`: the TMDB-vs-addon display
/// precedence, the credit/provider transforms, episode/season derivation, text formatting, and the
/// hero "up next" algorithm.
///
/// Built as a value from the view's current data on each access, so `MetaDetailView` keeps owning all
/// of its `@State` — this type holds no state and drives no observation. Everything here is a pure
/// function of its inputs (the Trakt-backed watch state for `upNext` is injected), so it's unit-testable
/// without SwiftUI, networking, or the shared services.
struct MetaDetailViewModel {
    let meta: Meta?
    let enrichment: Enrichment?
    let related: [MetaPreview]
    let typeID: String
    let metaID: String
    let fallbackTitle: String

    // MARK: - Background

    var backdropURL: URL? {
        (meta?.background ?? meta?.poster).flatMap(URL.init(string:)) ?? enrichment?.backdropURL
    }

    // MARK: - Hero up-next (series)

    /// The episode the hero Play targets for a series, plus its button label (Apple TV+ style — the
    /// button names the episode). nil for movies.
    struct UpNext {
        let video: Video
        let label: String
        let resumeProgress: Double?   // non-nil while this episode is mid-watch on Trakt
        let marksEpisode: Bool        // true for resume / next-unwatched; false for the "Rewatch" fallback
    }

    /// The show hero's episode: the last played episode if it isn't finished (resume), otherwise the
    /// next episode to watch — the one right after your furthest-watched episode. We use the *furthest*
    /// watched (not the earliest gap), so an old skipped episode can't drag the hero backward.
    ///
    /// `progress`/`isWatched` are injected (Trakt-backed in the app, faked in tests) so this stays a
    /// pure function of the episode list + watch state.
    func upNext(progress: (Video) -> Double?, isWatched: (Video) -> Bool) -> UpNext? {
        guard typeID == "series" else { return nil }
        let eps = allEpisodes
        guard !eps.isEmpty else { return nil }

        // 1. Last played but not finished → resume it.
        if let inProgress = eps.last(where: { progress($0) != nil }) {
            return UpNext(
                video: inProgress,
                label: "Resume \(seasonEpisodeLabel(inProgress))",
                resumeProgress: progress(inProgress),
                marksEpisode: true
            )
        }
        // 2. Next to watch → the episode right after the furthest-watched one.
        if let lastWatchedIdx = eps.lastIndex(where: { isWatched($0) }) {
            let nextIdx = eps.index(after: lastWatchedIdx)
            if nextIdx < eps.count {
                let next = eps[nextIdx]
                return UpNext(video: next, label: "Play \(seasonEpisodeLabel(next))", resumeProgress: nil, marksEpisode: true)
            }
            // Furthest-watched is the final episode → nothing left to watch next.
            return UpNext(video: eps[0], label: "Play", resumeProgress: nil, marksEpisode: false)
        }
        // 3. Nothing watched yet → the next to watch is the first episode.
        return UpNext(video: eps[0], label: "Play \(seasonEpisodeLabel(eps[0]))", resumeProgress: nil, marksEpisode: true)
    }

    // MARK: - Episodes & seasons

    var seasons: [Int] {
        guard let videos = meta?.videos else { return [] }
        return Array(Set(videos.compactMap { $0.season }).filter { $0 > 0 }).sorted()
    }

    /// Every episode from every season in one continuous list, ordered by season then episode.
    /// Apple TV's episode row is a single horizontal strip spanning all seasons — so moving right off
    /// the last episode of a season flows straight into the first episode of the next, with no per-season
    /// filtering. The season selector above is a "jump to" control rather than a filter.
    var allEpisodes: [Video] {
        (meta?.videos ?? [])
            .filter { ($0.season ?? 0) > 0 }
            .sorted {
                let s0 = $0.season ?? 0, s1 = $1.season ?? 0
                if s0 != s1 { return s0 < s1 }
                return ($0.episode ?? 0) < ($1.episode ?? 0)
            }
    }

    func seasonEpisodeLabel(_ episode: Video) -> String {
        "S\(episode.season ?? 0), E\(episode.episode ?? 0)"
    }

    /// Trakt playback/watched key for an episode: "showImdb:season:episode" (matches TraktService).
    func episodeKey(_ episode: Video) -> String {
        "\(metaID):\(episode.season ?? 0):\(episode.episode ?? 0)"
    }

    func episodeLabel(_ episode: Video) -> String {
        let s = episode.season ?? 0
        let e = episode.episode ?? 0
        let prefix = "S\(s)·E\(e)"
        if let title = episode.title, !title.isEmpty {
            return "\(prefix) — \(title)"
        }
        return prefix
    }

    /// Episode run time: real TMDB minutes (formatted via `FormatStyle`) when available, else the
    /// stable placeholder so the row stays populated for addons that don't provide per-episode runtime.
    func episodeDurationText(_ episode: Video, info: EpisodeEnrichment?) -> String {
        if let minutes = info?.runtimeMinutes, minutes > 0 {
            return Duration.seconds(minutes * 60)
                .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
        }
        return episodeDuration(episode)
    }

    /// Fallback per-episode runtime (used by `episodeDurationText` only when TMDB has none): a stable,
    /// varied value so the row still looks like Apple's (38m / 47m / 1h 2m) rather than blank.
    func episodeDuration(_ episode: Video) -> String {
        let n = episode.episode ?? 1
        let minutes = 42 + (n * 11) % 28
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    // MARK: - Related

    /// Related titles: prefer TMDB recommendations (real "viewers also watched") and fall back to the
    /// genre catalog when TMDB has nothing.
    var relatedItems: [MetaPreview] {
        if let recs = enrichment?.recommendations, !recs.isEmpty { return recs }
        return related
    }

    // MARK: - How to Watch

    /// Where the title is available to watch (TMDB/JustWatch, US), grouped by Stream / Rent / Buy.
    /// One card per provider, with its availabilities combined into the description (e.g. a provider
    /// offering both rent and buy shows once as "Rent/Buy"). Provider order follows first appearance
    /// across the priority-ordered groups (Stream → Rent → Buy …), so the labels join in that order.
    var watchOptions: [WatchOption] {
        var order: [Int] = []
        var byProvider: [Int: (provider: WatchProvider, labels: [String])] = [:]
        for group in enrichment?.watchProviderGroups ?? [] {
            for provider in group.providers {
                if byProvider[provider.id] == nil {
                    order.append(provider.id)
                    byProvider[provider.id] = (provider, [])
                }
                byProvider[provider.id]?.labels.append(group.label)
            }
        }
        return order.compactMap { id in
            byProvider[id].map {
                WatchOption(id: "\(id)", provider: $0.provider, availability: $0.labels.joined(separator: "/"))
            }
        }
    }

    // MARK: - Hero facts / chips

    var typeAndGenreParts: [String] {
        var parts = [StremioType.displayLabel(for: typeID)]
        let genres = displayGenres
        if !genres.isEmpty {
            parts.append(contentsOf: genres.prefix(2))
        }
        return parts
    }

    // PLACEHOLDER — used only until TMDB supplies a real certification (see `displayCertification`).
    var ratingPlaceholder: String {
        typeID == "series" ? "TV-MA" : "PG-13"
    }

    var factsLine: String {
        var parts: [String] = []
        if let year = meta?.releaseInfo, !year.isEmpty { parts.append(year) }
        if let runtime = displayRuntime { parts.append(runtime) }
        if let rating = meta?.imdbRating, !rating.isEmpty {
            parts.append("★ \(rating)")
        } else if let tmdb = enrichment?.rating, tmdb > 0 {
            parts.append("★ \(tmdb.formatted(.number.precision(.fractionLength(1))))")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - TMDB-merged display values
    //
    // Precedence: prefer the TMDB value for the *metadata* fields it improves on (overview, genres,
    // runtime, credits, certification/status/country/language) and fall back to addon `meta`. Artwork
    // (logo/backdrop) prefers the curated addon art (Metahub white wordmark / full-res background) and
    // uses TMDB only to fill a gap, since TMDB logos vary in style/colour. Nothing is ever blanked out.

    var displayLogoURL: URL? {
        meta?.logo.flatMap(URL.init(string:)) ?? enrichment?.logoURL
    }

    var displayDescription: String? {
        if let overview = enrichment?.overview, !overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return overview
        }
        return meta?.description
    }

    var displayGenres: [String] {
        if let genres = enrichment?.genres, !genres.isEmpty { return genres }
        return meta?.genres ?? []
    }

    /// Real TMDB certification ("PG-13" / "TV-MA") when available, else the placeholder.
    var displayCertification: String {
        if let certification = enrichment?.certification, !certification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return certification
        }
        return ratingPlaceholder
    }

    /// Run time, preferring TMDB minutes (formatted via `FormatStyle`) over the addon's string.
    var displayRuntime: String? {
        if let minutes = enrichment?.runtimeMinutes, minutes > 0 {
            return Duration.seconds(minutes * 60)
                .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
        }
        if let runtime = meta?.runtime, !runtime.isEmpty { return runtime }
        return nil
    }

    /// Cast names for the hero credits column, preferring TMDB's ordered cast.
    var displayCastNames: [String] {
        if let cast = enrichment?.cast, !cast.isEmpty { return cast.map(\.name) }
        return meta?.cast ?? []
    }

    var displayDirectors: [String] {
        if let directors = enrichment?.directors, !directors.isEmpty { return directors }
        return meta?.director ?? []
    }

    /// Combined cast + crew entries (with photos/roles) for the Cast & Crew row. Falls back to the
    /// addon's name-only cast/director when TMDB has nothing.
    var creditEntries: [CreditEntry] {
        if let e = enrichment, !e.cast.isEmpty || !e.directors.isEmpty || !e.writers.isEmpty {
            var entries = e.cast.prefix(12).map {
                CreditEntry(id: "cast-\($0.id)", name: $0.name, role: $0.character ?? "Cast", imageURL: $0.profileURL)
            }
            entries += e.directors.map { CreditEntry(id: "dir-\($0)", name: $0, role: "Director", imageURL: nil) }
            entries += e.writers.map { CreditEntry(id: "wri-\($0)", name: $0, role: "Writer", imageURL: nil) }
            return entries
        }
        var entries = (meta?.cast ?? []).prefix(12).enumerated().map { index, name in
            CreditEntry(id: "cast-\(index)-\(name)", name: name, role: "Cast", imageURL: nil)
        }
        entries += (meta?.director ?? []).enumerated().map { index, name in
            CreditEntry(id: "dir-\(index)-\(name)", name: name, role: "Director", imageURL: nil)
        }
        return entries
    }

    func airDate(_ released: String?) -> String? {
        guard let released, !released.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: released) ?? ISO8601DateFormatter().date(from: released)
        guard let date else { return String(released.prefix(10)) }
        let out = DateFormatter()
        out.dateFormat = "MMM d, yyyy"
        return out.string(from: date)
    }
}
