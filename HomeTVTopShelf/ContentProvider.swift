import Foundation
// TVServices isn't annotated for Swift concurrency; @preconcurrency silences the spurious
// Sendable warnings on its content/item types (which are only ever touched on this one task).
@preconcurrency import TVServices

/// Supplies HomeTV's dynamic Top Shelf as a large auto-scrolling hero carousel of popular titles
/// fetched from Cinemeta — the big edge-to-edge preview banner Apple shows behind a focused app
/// icon. Each item pairs wide landscape artwork with full details (synopsis, year, rating, runtime,
/// cast) and carries a `hometv://` deep link so selecting it opens that title in the app.
///
/// The popular catalog is public (no auth, no app state), so the extension fetches it directly
/// rather than sharing the app's addon registry through an App Group.
final class ContentProvider: TVTopShelfContentProvider {
    private static let base = URL(string: "https://v3-cinemeta.strem.io")

    /// The carousel is a glanceable hero, not a full catalog — cap how many titles it rotates through.
    private static let maxItems = 8

    override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        let items = await Self.fetchItems()
        // Nothing to show (e.g. offline) → hand back nil so tvOS falls back to the static Top
        // Shelf brand image rather than an empty carousel.
        return items.isEmpty ? nil : TVTopShelfCarouselContent(style: .details, items: items)
    }

    /// Picks the carousel candidates from the popular catalogs, fetches each one's full (Sendable)
    /// metadata concurrently while preserving order, then builds the carousel items.
    private static func fetchItems() async -> [TVTopShelfCarouselItem] {
        guard let base else { return [] }
        async let movies = previews(base: base, type: "movie", id: "top")
        async let series = previews(base: base, type: "series", id: "top")
        // Interleave movies and shows, keeping only titles with wide artwork (a poster looks wrong
        // in the hero frame), and take the first few as the banner candidates.
        let candidates = Array(
            interleave(await movies, await series)
                .filter { $0.background != nil }
                .prefix(maxItems)
        )

        let details = await fetchDetails(base: base, for: candidates)
        // Composite each hero (logo over background) concurrently; file URLs are Sendable, so the
        // non-Sendable carousel items get built synchronously afterwards.
        let heroes = await fetchHeroes(candidates: candidates, details: details)
        // Drop heroes left over from titles that have since rotated out of the popular catalog.
        HeroImageComposer.pruneHeroes(keeping: candidates.map(\.id))
        return zip(zip(candidates, details), heroes).compactMap { pair, hero in
            carouselItem(preview: pair.0, detail: pair.1, heroImageURL: hero)
        }
    }

    /// Composited hero artwork per candidate (nil when compositing fails), aligned by index.
    private static func fetchHeroes(candidates: [MetaPreview], details: [Meta?]) async -> [URL?] {
        await withTaskGroup(of: (Int, URL?).self) { group in
            for (index, pair) in zip(candidates, details).enumerated() {
                group.addTask { (index, await heroImageURL(preview: pair.0, detail: pair.1)) }
            }
            var result = [URL?](repeating: nil, count: candidates.count)
            for await (index, url) in group { result[index] = url }
            return result
        }
    }

    /// Renders the title-over-artwork hero, preferring full-meta artwork and falling back to the
    /// preview's. Returns nil (and the item uses the plain remote background) if there's no artwork.
    private static func heroImageURL(preview: MetaPreview, detail: Meta?) async -> URL? {
        guard let background = (detail?.background ?? preview.background).flatMap({ URL(string: $0) }) else {
            return nil
        }
        let logo = (detail?.logo ?? preview.logo).flatMap { URL(string: $0) }
        return await HeroImageComposer.makeHero(identifier: preview.id, backgroundURL: background, logoURL: logo)
    }

    private static func previews(base: URL, type: String, id: String) async -> [MetaPreview] {
        let response = try? await StremioClient.shared.catalog(baseURL: base, type: type, id: id)
        return response?.metas ?? []
    }

    /// Full metadata per candidate, fetched concurrently. Returns one slot per candidate (nil when a
    /// lookup fails) so the result stays aligned with `candidates` by index.
    private static func fetchDetails(base: URL, for candidates: [MetaPreview]) async -> [Meta?] {
        await withTaskGroup(of: (Int, Meta?).self) { group in
            for (index, preview) in candidates.enumerated() {
                group.addTask {
                    let meta = try? await StremioClient.shared.meta(baseURL: base, type: preview.type, id: preview.id)
                    return (index, meta?.meta)
                }
            }
            var result = [Meta?](repeating: nil, count: candidates.count)
            for await (index, meta) in group { result[index] = meta }
            return result
        }
    }

    /// Alternates the two catalogs (movie, show, movie, show, …) so the banner mixes content types.
    private static func interleave(_ first: [MetaPreview], _ second: [MetaPreview]) -> [MetaPreview] {
        var result: [MetaPreview] = []
        for index in 0..<max(first.count, second.count) {
            if index < first.count { result.append(first[index]) }
            if index < second.count { result.append(second[index]) }
        }
        return result
    }

    /// Builds one carousel item from a catalog preview and its (optional) full metadata. Falls back
    /// to the preview's own fields whenever the detail lookup failed.
    private static func carouselItem(preview: MetaPreview, detail: Meta?, heroImageURL: URL?) -> TVTopShelfCarouselItem? {
        // Prefer the composited title-over-artwork hero; fall back to the plain remote background.
        let url: URL?
        if let heroImageURL {
            url = heroImageURL
        } else if let artwork = detail?.background ?? preview.background {
            url = URL(string: artwork)
        } else {
            url = nil
        }
        guard let url else { return nil }

        let item = TVTopShelfCarouselItem(identifier: preview.id)
        item.title = detail?.name ?? preview.name
        item.contextTitle = StremioType.displayLabel(for: preview.type)
        item.summary = detail?.description ?? preview.description
        if let genres = detail?.genres ?? preview.genres, !genres.isEmpty {
            item.genre = genres.prefix(3).joined(separator: ", ")
        }
        if let seconds = runtimeSeconds(detail?.runtime) {
            item.duration = seconds
        }
        item.namedAttributes = namedAttributes(preview: preview, detail: detail)
        item.setImageURL(url, for: .screenScale1x)
        item.setImageURL(url, for: .screenScale2x)
        if let link = deepLink(for: preview) {
            let action = TVTopShelfAction(url: link)
            item.displayAction = action
            item.playAction = action
        }
        return item
    }

    /// The labeled chips shown under the synopsis in the `.details` style: year, IMDb rating, and
    /// (when known) director and top-billed cast.
    private static func namedAttributes(preview: MetaPreview, detail: Meta?) -> [TVTopShelfNamedAttribute] {
        var attributes: [TVTopShelfNamedAttribute] = []
        if let year = detail?.releaseInfo ?? preview.releaseInfo, !year.isEmpty {
            attributes.append(TVTopShelfNamedAttribute(name: "Released", values: [year]))
        }
        if let rating = detail?.imdbRating ?? preview.imdbRating, !rating.isEmpty {
            attributes.append(TVTopShelfNamedAttribute(name: "IMDb", values: [rating]))
        }
        if let director = detail?.director, !director.isEmpty {
            attributes.append(TVTopShelfNamedAttribute(name: "Director", values: Array(director.prefix(2))))
        }
        if let cast = detail?.cast, !cast.isEmpty {
            attributes.append(TVTopShelfNamedAttribute(name: "Cast", values: Array(cast.prefix(3))))
        }
        return attributes
    }

    /// Parses Cinemeta runtime strings (e.g. "148 min", "2h 28min", "1h") into seconds for the
    /// carousel's duration field. Returns nil when nothing parseable is found.
    private static func runtimeSeconds(_ runtime: String?) -> TimeInterval? {
        guard let runtime else { return nil }
        var hours = 0
        var minutes = 0
        var current = 0
        var hasDigits = false
        for character in runtime.lowercased() {
            if let digit = character.wholeNumberValue {
                current = current * 10 + digit
                hasDigits = true
            } else if character == "h", hasDigits {
                hours = current
                current = 0
                hasDigits = false
            } else if character == "m", hasDigits {
                minutes = current
                current = 0
                hasDigits = false
            }
        }
        // A bare trailing number with no unit (e.g. "148") is minutes.
        if hasDigits, hours == 0, minutes == 0 { minutes = current }
        let total = hours * 3600 + minutes * 60
        return total > 0 ? TimeInterval(total) : nil
    }

    /// `hometv://detail?type=movie&id=tt1234567&name=Title` — parsed by `DeepLinkRouter` in the app.
    private static func deepLink(for meta: MetaPreview) -> URL? {
        var components = URLComponents()
        components.scheme = "hometv"
        components.host = "detail"
        components.queryItems = [
            URLQueryItem(name: "type", value: meta.type),
            URLQueryItem(name: "id", value: meta.id),
            URLQueryItem(name: "name", value: meta.name)
        ]
        return components.url
    }
}
