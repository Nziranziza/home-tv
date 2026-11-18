import Foundation

/// Finds intros, recaps and credits among a file's chapters by their titles.
enum ChapterSegmentMatcher {
    private static let titles: [SkipSegment.Kind: Set<String>] = [
        .intro: ["intro", "opening", "op", "opening credits"],
        .recap: ["recap", "previously"],
        .credits: ["credits", "end credits", "ending", "ed", "outro"],
    ]

    static func kind(ofTitle title: String) -> SkipSegment.Kind? {
        let key = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return SkipSegment.Kind.allCases.first { titles[$0]?.contains(key) == true }
    }

    static func source(from chapters: [PlaybackChapter]) -> SkipSegmentSource {
        var source = SkipSegmentSource()
        for chapter in chapters {
            guard let kind = kind(ofTitle: chapter.title) else { continue }
            source.spans[kind, default: []].append(SkipSegmentSpan(start: chapter.start, end: chapter.end))
        }
        return source
    }
}
