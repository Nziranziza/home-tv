import Foundation
import Observation

struct WatchHistoryItem: Codable, Identifiable, Hashable, Sendable {
    let typeID: String
    let metaID: String
    let name: String
    let poster: String?
    let background: String?
    let logo: String?
    let viewedAt: Date
    /// When the title was *finished*, if ever known. Optional so history saved before this existed
    /// still decodes; see `WatchHistory.finishedItems` for how it's derived when nothing reports
    /// completion.
    var finishedAt: Date? = nil

    var id: String { "\(typeID):\(metaID)" }

    var preview: MetaPreview {
        MetaPreview(
            id: metaID,
            type: typeID,
            name: name,
            poster: poster,
            posterShape: nil,
            background: background,
            logo: logo,
            description: nil,
            releaseInfo: nil,
            imdbRating: nil,
            genres: nil
        )
    }

}

extension WatchHistoryItem {
    /// Adapt a `MetaPreview` (e.g. a Trakt continue-watching item) into the shape the Continue
    /// Watching row renders. In an extension so the struct keeps its memberwise initializer.
    init(preview: MetaPreview, viewedAt: Date = Date()) {
        self.init(
            typeID: preview.type,
            metaID: preview.id,
            name: preview.name,
            poster: preview.poster,
            background: preview.background,
            logo: preview.logo,
            viewedAt: viewedAt,
            finishedAt: nil
        )
    }
}

@Observable
@MainActor
final class WatchHistory {
    static let shared = WatchHistory()

    private(set) var items: [WatchHistoryItem] = []

    private let storageKey = "hometv.watchHistory.v1"
    private let defaults: UserDefaults
    private let limit: Int = 24

    /// How long after a title was played it is treated as finished, when nothing tells us otherwise.
    ///
    /// HomeTV hands playback to external players (Infuse/VLC), which never report completion back, so
    /// locally there is no real "finished" event to record — `markFinished(id:)` exists for when one
    /// is available, but signed out nothing calls it. Ageing items out of Continue Watching after a
    /// day is the honest local approximation: a title you played yesterday and haven't returned to is
    /// far more likely finished than still in progress. Trakt supersedes all of this when signed in.
    static let finishedAfter: TimeInterval = 60 * 60 * 24

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let env = ProcessInfo.processInfo.environment
        if env["RESET_HISTORY"] == "1" {
            defaults.removeObject(forKey: storageKey)
        }
        load()
        if env["SEED_HISTORY"] == "1" && items.isEmpty {
            items = WatchHistory.sampleItems()
            save()
        }
    }

    /// Locally in-progress titles — the Continue Watching source when not signed in to Trakt.
    var inProgressItems: [WatchHistoryItem] {
        items.filter { !isFinished($0) }
    }

    /// Locally finished titles, most recently finished first — the Recently Watched source when not
    /// signed in to Trakt. Disjoint from `inProgressItems`, so the two rows never show the same title.
    var finishedItems: [WatchHistoryItem] {
        items.filter(isFinished).sorted { ($0.finishedAt ?? $0.viewedAt) > ($1.finishedAt ?? $1.viewedAt) }
    }

    /// Record that a title was watched to the end. Nothing in the app can currently detect this (see
    /// `finishedAfter`); it's the seam for when a source of truth exists.
    func markFinished(id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].finishedAt == nil else {
            return
        }
        items[index].finishedAt = Date()
        save()
    }

    private func isFinished(_ item: WatchHistoryItem) -> Bool {
        if item.finishedAt != nil { return true }
        return Date().timeIntervalSince(item.viewedAt) >= Self.finishedAfter
    }

    private static func sampleItems() -> [WatchHistoryItem] {
        let samples: [(String, String, String)] = [
            ("movie", "tt0111161", "The Shawshank Redemption"),
            ("movie", "tt0468569", "The Dark Knight"),
            ("series", "tt0903747", "Breaking Bad"),
            ("movie", "tt0109830", "Forrest Gump"),
            ("series", "tt0944947", "Game of Thrones"),
            ("movie", "tt0816692", "Interstellar")
        ]
        let now = Date()
        return samples.enumerated().map { idx, entry in
            let (type, id, name) = entry
            // The back half of the sample set is seeded as *finished* (played days ago), so
            // SEED_HISTORY populates the Recently Watched row as well as Continue Watching.
            let isFinished = idx >= samples.count / 2
            let viewedAt = isFinished
                ? now.addingTimeInterval(-Double(idx) * 86_400)
                : now.addingTimeInterval(-Double(idx) * 3600)
            return WatchHistoryItem(
                typeID: type,
                metaID: id,
                name: name,
                poster: "https://images.metahub.space/poster/medium/\(id)/img",
                background: "https://images.metahub.space/background/medium/\(id)/img",
                logo: "https://images.metahub.space/logo/medium/\(id)/img",
                viewedAt: viewedAt,
                finishedAt: isFinished ? viewedAt : nil
            )
        }
    }

    func record(
        typeID: String,
        metaID: String,
        name: String,
        poster: String?,
        background: String?,
        logo: String?
    ) {
        let item = WatchHistoryItem(
            typeID: typeID,
            metaID: metaID,
            name: name,
            poster: poster,
            background: background,
            logo: logo,
            viewedAt: Date()
        )
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
        if items.count > limit {
            items = Array(items.prefix(limit))
        }
        save()
    }

    func remove(id: String) {
        items.removeAll { $0.id == id }
        save()
    }

    func clear() {
        items = []
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([WatchHistoryItem].self, from: data) else {
            return
        }
        items = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
