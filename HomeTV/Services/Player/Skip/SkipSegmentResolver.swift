import Foundation

/// Merges the sources' segments into what the button offers.
enum SkipSegmentResolver {
    /// Shorter segments are taken as bad data.
    static let minimumLength: TimeInterval = 5
    /// An end this far past the file still counts, as millisecond timestamps overshoot.
    static let endTolerance: TimeInterval = 2
    /// The button hides this long before a segment ends.
    static let endMargin: TimeInterval = 2

    /// For each kind, every valid segment from the first source that has one. Sources come in priority order.
    static func segments(from sources: [SkipSegmentSource], duration: TimeInterval) -> [SkipSegment] {
        guard duration > 0 else { return [] }
        let postCreditsStart = sources.lazy.compactMap(\.postCreditsStart).first { $0 > 0 && $0 < duration }
        return SkipSegment.Kind.allCases.flatMap { kind in
            let spans = sources.lazy
                .map { ($0.spans[kind] ?? []).compactMap { validated($0, duration: duration) } }
                .first { !$0.isEmpty } ?? []
            return spans.sorted { $0.start < $1.start }.compactMap { span in
                guard kind == .credits, let postCreditsStart, postCreditsStart > span.start else {
                    return SkipSegment(kind: kind, start: span.start, end: span.end)
                }
                // Credits stop where a scene after them starts, and Skip lands on it. Too little before the
                // scene leaves nothing to skip, so no button rather than a skip past the scene.
                let end = min(span.end, postCreditsStart)
                guard end - span.start >= minimumLength else { return nil }
                return SkipSegment(kind: kind, start: span.start, end: end, scene: postCreditsStart)
            }
        }
    }

    /// The span with its open ends filled in; nil with no bounds at all, or if inverted, too short or past
    /// the file's end.
    static func validated(_ span: SkipSegmentSpan, duration: TimeInterval) -> (start: TimeInterval, end: TimeInterval)? {
        guard span.start != nil || span.end != nil else { return nil }
        let start = span.start ?? 0
        let end = span.end ?? duration
        guard start >= 0, end <= duration + endTolerance else { return nil }
        let clampedEnd = min(end, duration)
        guard clampedEnd - start >= minimumLength else { return nil }
        return (start, clampedEnd)
    }

    /// The segment playing at `time`, until `endMargin` before its end.
    static func active(in segments: [SkipSegment], at time: TimeInterval) -> SkipSegment? {
        segments.first { time >= $0.start && time < $0.end - endMargin }
    }
}
