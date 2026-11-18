import AVFoundation

/// A chapter of the playing file.
struct PlaybackChapter: Equatable, Sendable {
    let start: TimeInterval
    let end: TimeInterval
    let title: String
}

extension PlaybackChapter {
    /// An AVFoundation asset's chapters, in the viewer's language when there's a choice.
    @MainActor
    static func load(from asset: AVAsset) async -> [PlaybackChapter] {
        guard let locales = try? await asset.load(.availableChapterLocales), !locales.isEmpty else { return [] }
        let languages = Locale.preferredLanguages + locales.map(\.identifier)
        guard let groups = try? await asset.loadChapterMetadataGroups(bestMatchingPreferredLanguages: languages) else {
            return []
        }
        var chapters: [PlaybackChapter] = []
        for group in groups {
            let item = AVMetadataItem.metadataItems(from: group.items, filteredByIdentifier: .commonIdentifierTitle).first
            let title = (try? await item?.load(.stringValue)) ?? nil
            let range = group.timeRange
            chapters.append(PlaybackChapter(start: range.start.seconds, end: range.end.seconds, title: title ?? ""))
        }
        return chapters
    }
}
