import Foundation

/// What the Info tab shows about the title, from its add-on meta.
struct PlayerTitleInfo: Equatable, Sendable {
    var posterURL: URL?
    /// The episode's overview for an episode, else the title's description.
    var synopsis: String?
    var genre: String?
    var runtimeSeconds: Int?
    /// The detail screen Go to Movie / Go to Show opens, with the meta's artwork.
    var detail: MetaPreview

    /// Merges `metas` from several add-ons, earlier ones winning. nil when there are none.
    static func merging(_ metas: [Meta], type: String, item: PlaybackItem) -> PlayerTitleInfo? {
        guard let first = metas.first else { return nil }
        func firstValue<T>(_ value: (Meta) -> T?) -> T? { metas.lazy.compactMap(value).first }
        let description = firstValue { $0.description.nonEmpty }
        let overview = firstValue { episodeOverview(in: $0, item: item) }
        // Only a poster that forms a URL, so a blank one doesn't hide a later add-on's.
        let poster = firstValue { meta in meta.poster.nonEmpty.flatMap { URL(string: $0) == nil ? nil : $0 } }
        return PlayerTitleInfo(
            posterURL: poster.flatMap(URL.init(string:)),
            synopsis: overview ?? description,
            genre: firstValue { $0.genres?.splitGenres().first },
            runtimeSeconds: firstValue { PlaybackSession.runtimeSeconds(from: $0.runtime) },
            detail: MetaPreview(
                id: item.showID,
                type: type,
                name: first.name,
                poster: poster,
                posterShape: nil,
                background: firstValue(\.background),
                logo: firstValue(\.logo),
                description: description,
                releaseInfo: firstValue(\.releaseInfo),
                imdbRating: firstValue(\.imdbRating),
                genres: firstValue(\.genres)
            )
        )
    }

    /// Whether later add-ons have nothing left to add. An episode keeps looking for its own overview, even
    /// with the show's description to fall back on.
    static func isComplete(_ metas: [Meta], type: String, item: PlaybackItem) -> Bool {
        guard let info = merging(metas, type: type, item: item), info.posterURL != nil, info.synopsis != nil,
              info.genre != nil, info.runtimeSeconds != nil else { return false }
        return item.season == nil || metas.contains { episodeOverview(in: $0, item: item) != nil }
    }

    private static func episodeOverview(in meta: Meta, item: PlaybackItem) -> String? {
        guard item.season != nil else { return nil }
        return meta.videos?.first { $0.id == item.contentID }?.overview.nonEmpty
    }
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let self, !self.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return self
    }
}
