import Foundation
import Observation

/// Drives the In Theaters & At Home row: the cards, the placeholder slots shown while they load, and
/// the TMDB → IMDB hop a selection needs.
///
/// Owned by the row (as `BrowseByGenreModel` is by its own) so the fetch — and the re-render when it
/// lands — stays inside the row and never re-evaluates the Watch Now page body or its lazy catalog rows.
@Observable
@MainActor
final class InTheatersModel {
    /// Slots held while loading: three, because three showcase cards is what fits across the screen.
    private static let placeholderCount = 3

    /// Tries before the row gives up and hides itself, and how long it waits between them.
    private static let loadAttempts = 3
    private static let retryDelay: Duration = .seconds(2)

    private(set) var items: [TheatricalItem] = []
    private(set) var placeholderSlots: [Int]

    /// The row draws nothing at all — not even its header — once the source has answered with nothing.
    var isVisible: Bool { !items.isEmpty || !placeholderSlots.isEmpty }

    private var hasLoaded = false
    private let service: TMDBService
    /// TMDB is optional, exactly as it is for enrichment — without a key this row can never fill, so it
    /// reserves no space and never asks.
    private let canLoad: Bool

    init(service: TMDBService = .shared) {
        self.service = service
        canLoad = service.isConfigured
        placeholderSlots = canLoad ? Array(0..<Self.placeholderCount) : []
    }

    func load() async {
        guard canLoad, !hasLoaded else { return }
        hasLoaded = true

        for attempt in 1...Self.loadAttempts {
            if let loaded = await service.theatricalItems() {
                items = loaded
                break
            }
            // Every window failed, which is a network blip rather than an empty row. The row hides
            // itself when it has nothing, and a hidden row has no `.task` left to fire again — so the
            // only retry it will ever get is this one.
            guard attempt < Self.loadAttempts, !Task.isCancelled else { break }
            try? await Task.sleep(for: Self.retryDelay)
        }
        placeholderSlots = []
    }

    /// Resolve a card to something the detail screen can open. The cards come from TMDB lists, which
    /// carry no IMDB id, so the preview holds a `TMDBRef` and we bridge it on select — the same hop the
    /// Related row and the cast screen make. Returns nil when TMDB has no IMDB id for the title, which
    /// is also the only case where the addon-backed detail screen could not have loaded it.
    func resolved(_ item: TheatricalItem) async -> MetaPreview? {
        let preview = item.preview
        guard let ref = TMDBRef(encodedID: preview.id) else { return preview }
        guard let imdbID = await service.imdbID(for: ref) else { return nil }
        return MetaPreview(
            id: imdbID,
            type: preview.type,
            name: preview.name,
            poster: preview.poster,
            posterShape: nil,
            background: preview.background,
            logo: nil,
            description: preview.description,
            releaseInfo: preview.releaseInfo,
            imdbRating: nil,
            genres: preview.genres
        )
    }
}
