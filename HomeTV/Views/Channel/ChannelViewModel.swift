import Foundation
import Observation

/// Composes one streaming channel's screen: its wordmark, a hero and Top 10 from its most popular
/// titles, and the shelves beneath them.
@Observable
@MainActor
final class ChannelViewModel {
    let channel: StreamingChannel
    private let service: ChannelCatalogService

    private(set) var topTen: [MetaPreview] = []
    /// Rows wait for the hero, so the screen's first focus lands on Play rather than Top 10.
    private(set) var isLoaded = false
    private(set) var heroItems: [MetaPreview] = []
    private(set) var wordmarkURL: URL?

    var shelves: [ChannelShelf] { ChannelShelf.rows }

    init(channel: StreamingChannel, service: ChannelCatalogService = .shared) {
        self.channel = channel
        self.service = service
    }

    func load() async {
        async let titles = service.titles(for: channel, shelf: .topTen)
        async let wordmark = service.wordmarkURL(for: channel)
        let top = ChannelTitles.topTen(await titles ?? [])
        wordmarkURL = await wordmark
        heroItems = await service.heroItems(from: Array(top.prefix(ChannelTitles.heroLimit)))
        topTen = top
        isLoaded = true
    }

    /// Shelf cards carry a TMDB id; the detail screen needs the IMDB one. Nil when TMDB has none.
    func resolved(_ meta: MetaPreview) async -> MetaPreview? {
        guard let ref = TMDBRef(encodedID: meta.id) else { return meta }
        guard let imdbID = await TMDBService.shared.imdbID(for: ref) else { return nil }
        return ChannelTitles.heroPreview(meta, imdbID: imdbID, logo: nil)
    }
}
