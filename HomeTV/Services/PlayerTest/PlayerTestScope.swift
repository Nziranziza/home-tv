import Foundation

/// The files one browser screen searches within, and how it introduces them.
struct PlayerTestScope: Sendable {
    let title: String
    let summary: String
    let symbol: String
    let entries: [PlayerTestEntry]
    /// Files in Caches, whose empty state explains how to copy them over.
    let isLocal: Bool
    /// The filters worth offering: those with more than one value here.
    let facets: [(facet: PlayerTestFacet, options: [PlayerTestFacetOption])]

    init(title: String, summary: String, symbol: String, entries: [PlayerTestEntry], isLocal: Bool = false) {
        self.isLocal = isLocal
        self.title = title
        self.summary = summary
        self.symbol = symbol
        self.entries = entries
        facets = PlayerTestFacet.allCases.compactMap { facet in
            let options = facet.options(in: entries)
            return options.count > 1 ? (facet, options) : nil
        }
    }

    static func symbol(forSection id: String) -> String {
        switch id {
        case "modern": "sparkles.tv"
        case "bitrate": "speedometer"
        case "hdr": "sun.max"
        case "matrix": "square.grid.3x3"
        case "chromium": "globe"
        case "video": "film"
        case "audio": "waveform"
        case "subtitles": "captions.bubble"
        case "containers": "shippingbox"
        case "3d": "cube"
        case "broken": "exclamationmark.triangle"
        case "fail": "xmark.octagon"
        default: "square.stack"
        }
    }
}
