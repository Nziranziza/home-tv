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
    /// The row card the screen opened from. Its art is shown before `meta` loads and kept after, so the
    /// backdrop and logo never swap mid-reveal.
    var seed: MetaPreview? = nil

    // MARK: - Background

    var backdropURL: URL? {
        (seed?.background ?? meta?.background ?? meta?.poster ?? seed?.poster).flatMap(URL.init(string:))
            ?? enrichment?.backdropURL
    }

    // MARK: - Hero up-next (series)

    /// The episode the hero Play targets for a series, plus its button label (Apple TV+ style — the
    /// button names the episode). nil for movies.
    struct UpNext {
        let video: Video
        let label: String
        let resumeProgress: Double?   // non-nil while this episode is mid-watch on Trakt
        let marksEpisode: Bool        // true for resume / next-unwatched; false for the "Rewatch" fallback
        /// The show is under way, so the hero describes this episode instead of the show (Apple TV+ style).
        var describesEpisode = true
    }


    /// The show hero's episode, decided only by the last played episode (newest play activity): resume
    /// it if unfinished, else play the one after it, else Rewatch from the start after the finale.
    /// With no activity known, falls back to resuming the latest in-progress episode or playing the one
    /// after the furthest watched.
    ///
    /// Watch state is injected (library-backed in the app, faked in tests) so this stays pure. `eps` is
    /// the cached, already-sorted `MetaDetailModel.sortedEpisodes`.
    func upNext(
        episodes eps: [Video],
        progress: (Video) -> Double?,
        isWatched: (Video) -> Bool,
        lastPlayed: (Video) -> PlayActivity?
    ) -> UpNext? {
        guard typeID == "series" else { return nil }
        guard !eps.isEmpty else { return nil }

        var last: (index: Int, activity: PlayActivity)?
        for (index, episode) in eps.enumerated() {
            // `>=` so a tie goes to the later episode.
            guard let activity = lastPlayed(episode), activity.date >= last?.activity.date ?? .distantPast else { continue }
            last = (index, activity)
        }
        if let last {
            guard last.activity.isFinished else { return play(eps[last.index], progress: progress) }
            let nextIdx = eps.index(after: last.index)
            guard nextIdx < eps.count else { return rewatch(eps) }
            return play(eps[nextIdx], progress: progress)
        }

        // No activity known: resume the latest in-progress episode…
        if let inProgress = eps.last(where: { progress($0) != nil }) {
            return play(inProgress, progress: progress)
        }
        // …else the one after the furthest watched, so an old skipped episode can't drag it backward.
        if let lastWatchedIdx = eps.lastIndex(where: { isWatched($0) }) {
            let nextIdx = eps.index(after: lastWatchedIdx)
            guard nextIdx < eps.count else { return rewatch(eps) }
            return play(eps[nextIdx], progress: progress)
        }
        return UpNext(video: eps[0], label: "Play First Episode", resumeProgress: nil, marksEpisode: true, describesEpisode: false)
    }

    /// Resume `episode` if it has progress, otherwise play it from the start.
    private func play(_ episode: Video, progress: (Video) -> Double?) -> UpNext {
        let resume = progress(episode)
        let verb = resume == nil ? "Play" : "Resume"
        return UpNext(video: episode, label: "\(verb) \(seasonEpisodeLabel(episode))", resumeProgress: resume, marksEpisode: true)
    }

    /// What's left of a part-watched episode ("43m", "1h 2m"), or nil without a runtime.
    func timeLeftText(progress: Double, runtimeMinutes: Int?) -> String? {
        guard let runtimeMinutes, runtimeMinutes > 0 else { return nil }
        let minutes = max(1, Int((Double(runtimeMinutes) * (1 - progress)).rounded()))
        return Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }

    /// Nothing left to watch: start the show over, without targeting an episode.
    private func rewatch(_ eps: [Video]) -> UpNext {
        UpNext(video: eps[0], label: "Rewatch", resumeProgress: nil, marksEpisode: false, describesEpisode: false)
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
        if let title = episode.episodeTitle {
            return "\(prefix) — \(title)"
        }
        return prefix
    }

    /// Episode run time: real TMDB minutes (formatted via `FormatStyle`) when available, else the
    /// stable placeholder so the row stays populated for addons that don't provide per-episode runtime.
    /// `width` is `.narrow` ("1h 9m") for the compact card overlay and `.abbreviated` ("1 hr 9 min") for
    /// the episode hero / info, matching the reference.
    func episodeDurationText(
        _ episode: Video,
        info: EpisodeEnrichment?,
        width: Duration.UnitsFormatStyle.UnitWidth = .narrow
    ) -> String {
        if let minutes = info?.runtimeMinutes, minutes > 0 {
            return Duration.seconds(minutes * 60)
                .formatted(.units(allowed: [.hours, .minutes], width: width))
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
        let genres = displayGenres.splitGenres()
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
        if let year = displayYear { parts.append(year) }
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
        (seed?.logo ?? meta?.logo).flatMap(URL.init(string:)) ?? enrichment?.logoURL
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

    /// Release year, preferring TMDB and falling back to the addon's `releaseInfo` — the same TMDB-first,
    /// Cinemeta-fallback precedence as `displayGenres` / `displayRuntime`. This is why the year previously
    /// vanished on titles whose addon `meta.releaseInfo` was empty: there was no TMDB fallback.
    var displayYear: String? {
        if let year = enrichment?.year, !year.isEmpty { return year }
        if let year = meta?.releaseInfo, !year.isEmpty { return year }
        return nil
    }

    /// Real TMDB certification ("PG-13" / "TV-MA") when available, else the placeholder.
    var displayCertification: String {
        if let certification = enrichment?.certification, !certification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return certification
        }
        return ratingPlaceholder
    }

    /// Run time ("1h 9m"), preferring TMDB minutes over the addon's string. An addon "53 min" is
    /// reformatted the same way; anything else shows as given.
    var displayRuntime: String? {
        if let minutes = enrichment?.runtimeMinutes ?? Self.addonMinutes(meta?.runtime),
           Self.plausibleMinutes.contains(minutes) {
            return Duration.seconds(minutes * 60)
                .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
        }
        if let runtime = meta?.runtime, !runtime.isEmpty { return runtime }
        return nil
    }

    /// A runtime outside this is bad data; it would also overflow converting to seconds.
    static let plausibleMinutes = 1...10_000

    /// Minutes from an addon runtime written as minutes ("53 min"); nil for any other form ("2 h").
    static func addonMinutes(_ runtime: String?) -> Int? {
        let parts = runtime?.split(separator: " ") ?? []
        guard parts.count == 2, parts[1].lowercased().hasPrefix("min"),
              let minutes = Int(parts[0]), plausibleMinutes.contains(minutes) else { return nil }
        return minutes
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
                CreditEntry(id: "cast-\($0.id)", name: $0.name, role: $0.character ?? "Cast",
                            imageURL: $0.profileURL, personID: $0.id)
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
        // Parse the ISO-8601 release timestamp (with or without fractional seconds) via FormatStyle.
        let date = (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(released))
            ?? (try? Date.ISO8601FormatStyle().parse(released))
        // Date-only / unparseable strings fall back to the leading "yyyy-MM-dd", as before.
        guard let date else { return String(released.prefix(10)) }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}
