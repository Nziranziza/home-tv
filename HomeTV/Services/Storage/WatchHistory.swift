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
            viewedAt: viewedAt
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
            return WatchHistoryItem(
                typeID: type,
                metaID: id,
                name: name,
                poster: "https://images.metahub.space/poster/medium/\(id)/img",
                background: "https://images.metahub.space/background/medium/\(id)/img",
                logo: "https://images.metahub.space/logo/medium/\(id)/img",
                viewedAt: now.addingTimeInterval(-Double(idx) * 3600)
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
