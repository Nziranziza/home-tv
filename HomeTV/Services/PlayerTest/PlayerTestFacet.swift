import Foundation

/// A criterion the browser filters by.
enum PlayerTestFacet: String, CaseIterable, Identifiable, Sendable {
    case section, group, container, video, audio, resolution, hdr, result

    var id: String { rawValue }

    var title: String {
        switch self {
        case .section: "Section"
        case .group: "Group"
        case .container: "Container"
        case .video: "Video"
        case .audio: "Audio"
        case .resolution: "Resolution"
        case .hdr: "HDR"
        case .result: "Expected"
        }
    }

    func value(of entry: PlayerTestEntry) -> String? {
        switch self {
        case .section: entry.sectionTitle
        case .group: entry.groupTitle
        case .container: entry.item.container
        case .video: entry.item.video
        case .audio: entry.item.audio
        case .resolution: entry.item.resolution
        case .hdr: entry.item.hdr
        case .result: entry.expect.rawValue
        }
    }

    func displayName(_ value: String) -> String {
        switch self {
        case .container: value.uppercased()
        case .video, .audio: PlayerTestVocabulary.codecName(value)
        case .hdr: PlayerTestVocabulary.hdrName(value)
        case .result: PlayerTestExpectation(rawValue: value)?.title ?? value
        case .section, .group, .resolution: value
        }
    }

    /// The values present in `entries`, with how many entries have each.
    func options(in entries: [PlayerTestEntry]) -> [PlayerTestFacetOption] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for entry in entries {
            guard let value = value(of: entry) else { continue }
            if counts[value] == nil { order.append(value) }
            counts[value, default: 0] += 1
        }
        let options = order.map { PlayerTestFacetOption(value: $0, title: displayName($0), count: counts[$0] ?? 0) }
        switch self {
        // Catalog order already reads well for these.
        case .section, .group: return options
        case .result:
            let rank = PlayerTestExpectation.allCases.map(\.rawValue)
            return options.sorted { (rank.firstIndex(of: $0.value) ?? 0) < (rank.firstIndex(of: $1.value) ?? 0) }
        default:
            return options.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }
}
