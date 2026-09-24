import Foundation

/// Loads streaming channels from TMDB: each shelf's titles, the hero's resolved titles, and the
/// channel's wordmark. Results are cached for the session and concurrent requests coalesce.
actor ChannelCatalogService {
    static let shared = ChannelCatalogService()

    private let client: TMDBClient
    private var titleCache: [String: [MetaPreview]] = [:]
    private var titleInFlight: [String: Task<ShelfResult?, Never>] = [:]
    private var wordmarkCache: [Int: URL] = [:]

    /// Whether every media request answered; a partial shelf is shown but not cached.
    private struct ShelfResult: Sendable {
        let titles: [MetaPreview]
        let isComplete: Bool
    }

    init(client: TMDBClient = .shared) {
        self.client = client
    }

    nonisolated var isConfigured: Bool { TMDBConfig.isConfigured }

    /// A shelf's titles, or nil when every query for it failed.
    func titles(for channel: StreamingChannel, shelf: ChannelShelf) async -> [MetaPreview]? {
        guard isConfigured else { return [] }
        let key = "\(channel.providerID):\(shelf.id)"
        if let cached = titleCache[key] { return cached }
        if let inFlight = titleInFlight[key] { return await inFlight.value?.titles }

        let client = client
        let task = Task { () -> ShelfResult? in
            let today = Date.now
            let pages = await withTaskGroup(of: (Int, [MetaPreview]?).self) { group in
                for (index, media) in shelf.media.enumerated() {
                    let parameters = shelf.parameters(
                        media: media, providerID: channel.providerID, region: TMDBConfig.region, today: today
                    )
                    group.addTask {
                        let page = try? await client.discover(mediaType: media.rawValue, parameters: parameters)
                        return (index, page?.results.compactMap { ChannelTitles.preview(from: $0, media: media) })
                    }
                }
                var byIndex: [Int: [MetaPreview]] = [:]
                for await (index, page) in group {
                    if let page { byIndex[index] = page }
                }
                return shelf.media.indices.compactMap { byIndex[$0] }
            }
            guard !pages.isEmpty else { return nil }
            return ShelfResult(titles: ChannelTitles.interleave(pages), isComplete: pages.count == shelf.media.count)
        }
        titleInFlight[key] = task
        let result = await task.value
        titleInFlight[key] = nil
        if let result, result.isComplete { titleCache[key] = result.titles }
        return result?.titles
    }

    /// The previews that have a backdrop and an IMDB id, re-keyed to it and given their title logo.
    func heroItems(from previews: [MetaPreview]) async -> [MetaPreview] {
        let client = client
        let candidates = previews.filter { $0.background != nil }
        let resolved = await withTaskGroup(of: (Int, MetaPreview?).self) { group in
            for (index, preview) in candidates.enumerated() {
                guard let ref = TMDBRef(encodedID: preview.id) else { continue }
                group.addTask {
                    guard let summary = try? await client.titleSummary(mediaType: ref.mediaType, id: ref.id),
                          let imdbID = summary.externalIds?.imdbId, !imdbID.isEmpty else { return (index, nil) }
                    let logo = TMDBConfig.imageURL(path: ChannelTitles.preferredLogoPath(summary.images), size: .w500)
                    return (index, ChannelTitles.heroPreview(preview, imdbID: imdbID, logo: logo))
                }
            }
            var byIndex: [Int: MetaPreview] = [:]
            for await (index, preview) in group {
                if let preview { byIndex[index] = preview }
            }
            return candidates.indices.compactMap { byIndex[$0] }
        }
        return resolved
    }

    func wordmarkURL(for channel: StreamingChannel) async -> URL? {
        if let cached = wordmarkCache[channel.networkID] { return cached }
        guard isConfigured,
              let network = try? await client.network(id: channel.networkID),
              let url = TMDBConfig.imageURL(path: network.logoPath, size: .w500) else { return nil }
        wordmarkCache[channel.networkID] = url
        return url
    }
}
