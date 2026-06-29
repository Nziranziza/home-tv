import Foundation

enum StremioType: String, Codable, Hashable, Sendable {
    case movie
    case series
    case channel
    case tv
    case other

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = StremioType(rawValue: raw) ?? .other
    }
}

extension StremioType {
    /// Human-facing label for a raw Stremio `type` string ("movie" → "Movie", "series" → "TV Show",
    /// …), preserving the original (capitalized) for unknown types. Shared by the hero, catalog
    /// cards, and the detail screen so the label reads identically everywhere.
    static func displayLabel(for rawType: String) -> String {
        switch rawType {
        case "movie": "Movie"
        case "series": "TV Show"
        case "channel": "Channel"
        case "tv": "Live TV"
        default: rawType.capitalized
        }
    }
}

struct StremioManifest: Codable, Hashable, Sendable {
    let id: String
    let version: String?
    let name: String
    let description: String?
    let logo: String?
    let background: String?
    let resources: [AddonResource]?
    let types: [String]?
    let catalogs: [CatalogDescriptor]?
    let idPrefixes: [String]?
}

/// A manifest `resources` entry. Per the Stremio addon spec this is either the
/// short form (a bare string like `"stream"`) or the full form (an object with
/// `name`, `types`, `idPrefixes`). Cinemeta uses the short form; Torrentio uses
/// the full form, so we decode both.
struct AddonResource: Codable, Hashable, Sendable {
    let name: String
    let types: [String]?
    let idPrefixes: [String]?

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let raw = try? single.decode(String.self) {
            name = raw
            types = nil
            idPrefixes = nil
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        types = try container.decodeIfPresent([String].self, forKey: .types)
        idPrefixes = try container.decodeIfPresent([String].self, forKey: .idPrefixes)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(types, forKey: .types)
        try container.encodeIfPresent(idPrefixes, forKey: .idPrefixes)
    }

    private enum CodingKeys: String, CodingKey {
        case name, types, idPrefixes
    }
}

struct CatalogDescriptor: Codable, Hashable, Sendable {
    let type: String
    let id: String
    let name: String?
    let extra: [CatalogExtra]?
}

struct CatalogExtra: Codable, Hashable, Sendable {
    let name: String
    let isRequired: Bool?
    let options: [String]?
}

struct CatalogResponse: Codable, Sendable {
    let metas: [MetaPreview]
}

struct MetaPreview: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let type: String
    let name: String
    let poster: String?
    let posterShape: String?
    let background: String?
    let logo: String?
    let description: String?
    let releaseInfo: String?
    let imdbRating: String?
    let genres: [String]?

    /// A preview carrying only the identity the detail screen needs; artwork and full metadata are
    /// loaded from `id` once it appears. Shared by the deep-link router and the INITIAL_DETAIL
    /// launch path, which both open detail knowing nothing but the type/id (and maybe a name).
    static func placeholder(type: String, id: String, name: String = "Loading…") -> MetaPreview {
        MetaPreview(
            id: id,
            type: type,
            name: name,
            poster: nil,
            posterShape: nil,
            background: nil,
            logo: nil,
            description: nil,
            releaseInfo: nil,
            imdbRating: nil,
            genres: nil
        )
    }
}

struct MetaResponse: Codable, Sendable {
    let meta: Meta
}

struct Meta: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let type: String
    let name: String
    let poster: String?
    let background: String?
    let logo: String?
    let description: String?
    let releaseInfo: String?
    let runtime: String?
    let imdbRating: String?
    let genres: [String]?
    let cast: [String]?
    let director: [String]?
    let videos: [Video]?
}

struct Video: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String?
    let season: Int?
    let episode: Int?
    let released: String?
    let overview: String?
    let thumbnail: String?
}

struct StreamResponse: Codable, Sendable {
    let streams: [Stream]
}

struct Stream: Codable, Hashable, Sendable, Identifiable {
    let name: String?
    let title: String?
    let description: String?
    let url: String?
    let ytId: String?
    let infoHash: String?
    let fileIdx: Int?
    let sources: [String]?
    let behaviorHints: StreamBehaviorHints?

    var id: String {
        if let url { return url }
        if let infoHash {
            return "magnet:\(infoHash)#\(fileIdx ?? 0)"
        }
        if let ytId { return "yt:\(ytId)" }
        return UUID().uuidString
    }

    var displayTitle: String {
        title ?? name ?? "Stream"
    }

    var magnetURL: URL? {
        guard let infoHash else { return nil }
        var components = URLComponents()
        components.scheme = "magnet"
        var items: [URLQueryItem] = [URLQueryItem(name: "xt", value: "urn:btih:\(infoHash)")]
        if let title { items.append(URLQueryItem(name: "dn", value: title)) }
        for source in sources ?? [] {
            items.append(URLQueryItem(name: "tr", value: source))
        }
        components.queryItems = items
        return components.url
    }

    var playableURL: URL? {
        if let url, let u = URL(string: url) { return u }
        if let magnetURL { return magnetURL }
        return nil
    }
}

struct StreamBehaviorHints: Codable, Hashable, Sendable {
    let bingeGroup: String?
    let notWebReady: Bool?
    let proxyHeaders: [String: String]?
}
