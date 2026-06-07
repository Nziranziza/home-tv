import Foundation

/// Pure filtering / grouping logic for `StreamPickerView`: the provider and quality filter axes and
/// the quality-sectioned list derived from the loaded streams and the two selected filters.
///
/// Built as a value from the view's current state on each access, so `StreamPickerView` keeps owning
/// all of its `@State`; this holds no state and drives no observation. Quality ordering reuses
/// `StreamPickerView.qualityRank` (also used by `StreamMeta`), and `StreamPickerView.allLabel` is the
/// shared "All" aggregate option.
struct StreamPickerViewModel {
    let streams: [StreamPickerView.LabeledStream]
    let selectedProvider: String
    let selectedQuality: String
    let detailID: String?

    private var allLabel: String { StreamPickerView.allLabel }

    /// "All" + distinct provider names in load order.
    var providers: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for item in streams where !seen.contains(item.addonName) {
            seen.insert(item.addonName)
            ordered.append(item.addonName)
        }
        return [allLabel] + ordered
    }

    var providerStreams: [StreamPickerView.LabeledStream] {
        guard selectedProvider != allLabel else { return streams }
        return streams.filter { $0.addonName == selectedProvider }
    }

    /// "All" + the quality buckets present for the selected provider, high → low.
    var qualities: [String] {
        let buckets = Set(providerStreams.map { $0.meta.resolution })
        let ordered = buckets.sorted { StreamPickerView.qualityRank($0) > StreamPickerView.qualityRank($1) }
        return [allLabel] + ordered
    }

    var filteredStreams: [StreamPickerView.LabeledStream] {
        guard selectedQuality != allLabel else { return providerStreams }
        return providerStreams.filter { $0.meta.resolution == selectedQuality }
    }

    /// Filtered streams grouped into quality sections, high → low.
    var qualitySections: [(quality: String, items: [StreamPickerView.LabeledStream])] {
        let groups = Dictionary(grouping: filteredStreams, by: { $0.meta.resolution })
        return groups.keys
            .sorted { StreamPickerView.qualityRank($0) > StreamPickerView.qualityRank($1) }
            .map { ($0, groups[$0] ?? []) }
    }

    var firstStreamID: String? { qualitySections.first?.items.first?.id }

    var detailStream: StreamPickerView.LabeledStream? {
        if let id = detailID, let match = filteredStreams.first(where: { $0.id == id }) { return match }
        return filteredStreams.first
    }

    func videoSpec(_ m: StreamMeta) -> String {
        let spec = [m.codec, m.bitDepth].compactMap { $0 }.joined(separator: " · ")
        return spec.isEmpty ? "—" : spec
    }
}
