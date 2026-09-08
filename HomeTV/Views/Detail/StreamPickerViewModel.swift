import Foundation

/// Pure filtering / grouping logic for `StreamPickerView`: the provider and quality filter axes and
/// the quality-sectioned list derived from the loaded streams and the two selected filters.
///
/// Built as a value from the view's current state on each access, so `StreamPickerView` keeps owning
/// all of its `@State`; this holds no state and drives no observation. Quality ordering reuses
/// `StreamPickerView.qualityRank` (also used by `StreamMeta`), and `StreamPickerView.allLabel` is the
/// shared "All" aggregate option.
struct StreamPickerViewModel {
    /// "All" + distinct provider names in load order.
    let providers: [String]
    let providerStreams: [StreamPickerView.LabeledStream]
    /// "All" + the quality buckets present for the selected provider, high → low.
    let qualities: [String]
    let filteredStreams: [StreamPickerView.LabeledStream]
    /// Filtered streams grouped into quality sections, high → low.
    let qualitySections: [(quality: String, items: [StreamPickerView.LabeledStream])]
    let firstStreamID: String?
    let detailStream: StreamPickerView.LabeledStream?

    /// Computes the whole filter/group cascade ONCE at construction and stores the results, so reading any
    /// derived property is O(1). Previously each was a computed property that re-ran the cascade on every
    /// access — and the view reads `firstStreamID` per row, so building/reading a fresh model per row made
    /// the list O(n²) on every focus move. Now the view builds one model and reads its stored fields.
    init(
        streams: [StreamPickerView.LabeledStream],
        selectedProvider: String,
        selectedQuality: String,
        detailID: String?
    ) {
        let allLabel = StreamPickerView.allLabel

        var seen = Set<String>()
        var ordered: [String] = []
        for item in streams where !seen.contains(item.addonName) {
            seen.insert(item.addonName)
            ordered.append(item.addonName)
        }
        self.providers = [allLabel] + ordered

        let providerStreams = selectedProvider == allLabel
            ? streams
            : streams.filter { $0.addonName == selectedProvider }
        self.providerStreams = providerStreams

        let buckets = Set(providerStreams.map { $0.meta.resolution })
        self.qualities = [allLabel] + buckets.sorted { StreamPickerView.qualityRank($0) > StreamPickerView.qualityRank($1) }

        let filteredStreams = selectedQuality == allLabel
            ? providerStreams
            : providerStreams.filter { $0.meta.resolution == selectedQuality }
        self.filteredStreams = filteredStreams

        let groups = Dictionary(grouping: filteredStreams, by: { $0.meta.resolution })
        let sections = groups.keys
            .sorted { StreamPickerView.qualityRank($0) > StreamPickerView.qualityRank($1) }
            .map { (quality: $0, items: groups[$0] ?? []) }
        self.qualitySections = sections

        self.firstStreamID = sections.first?.items.first?.id

        if let id = detailID, let match = filteredStreams.first(where: { $0.id == id }) {
            self.detailStream = match
        } else {
            self.detailStream = filteredStreams.first
        }
    }

    func videoSpec(_ m: StreamMeta) -> String {
        let spec = [m.codec, m.bitDepth].compactMap { $0 }.joined(separator: " · ")
        return spec.isEmpty ? "—" : spec
    }
}
