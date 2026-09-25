import Foundation
import Observation

/// Drives the Explore Channels & Apps row: per channel, key art from its most popular title, its
/// wordmark, and a panel colour sampled from that wordmark.
@Observable
@MainActor
final class ExploreChannelsModel {
    private let service: ChannelCatalogService

    let channels: [StreamingChannel]
    private(set) var keyArt: [Int: URL] = [:]
    /// Each channel's top posters, from which `keyArt` picks one no earlier card already shows.
    private var artCandidates: [Int: [URL]] = [:]
    private(set) var wordmarks: [Int: URL] = [:]
    private(set) var brandColors: [Int: BrandColor] = [:]

    init(service: ChannelCatalogService = .shared, channels: [StreamingChannel] = StreamingChannel.featured) {
        self.service = service
        self.channels = service.isConfigured ? channels : []
    }

    func brandColor(for channel: StreamingChannel) -> BrandColor { brandColors[channel.id] ?? .neutral }

    /// Publishes each channel as it resolves, so one slow request doesn't hold back the rest.
    func load() async {
        let service = service
        await withTaskGroup(of: (Int, [URL], URL?, BrandColor?).self) { group in
            for channel in channels where wordmarks[channel.id] == nil || keyArt[channel.id] == nil {
                group.addTask {
                    async let titles = service.titles(for: channel, shelf: .topTen)
                    async let wordmark = service.wordmarkURL(for: channel)
                    let art = (await titles ?? []).prefix(Self.artCandidateDepth).compactMap { $0.poster.flatMap(URL.init(string:)) }
                    let logo = await wordmark
                    let brand = await Self.brandColor(logo: logo)
                    return (channel.id, art, logo, brand)
                }
            }
            for await (id, art, logo, brand) in group {
                guard !Task.isCancelled else { return }
                if !art.isEmpty {
                    artCandidates[id] = art
                    keyArt = Self.assignArtwork(channels: channels.map(\.id), candidates: artCandidates)
                }
                if let logo { wordmarks[id] = logo }
                if let brand { brandColors[id] = brand.panel }
            }
        }
    }

    private static let artCandidateDepth = 6

    /// In row order, each channel takes its highest-ranked poster that no earlier channel has taken,
    /// falling back to its top one when every candidate is claimed.
    static func assignArtwork(channels: [Int], candidates: [Int: [URL]]) -> [Int: URL] {
        var assigned: [Int: URL] = [:]
        var claimed = Set<URL>()
        for id in channels {
            guard let options = candidates[id], let top = options.first else { continue }
            let pick = options.first { !claimed.contains($0) } ?? top
            assigned[id] = pick
            claimed.insert(pick)
        }
        return assigned
    }

    private nonisolated static func brandColor(logo: URL?) async -> BrandColor? {
        guard let logo,
              let image = try? await ImageLoader.shared.image(for: logo, targetSize: Theme.Channel.logoMaxSize),
              let cgImage = image.cgImage else { return nil }
        return BrandColor(averaging: cgImage)
    }
}
