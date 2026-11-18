import Foundation

/// A segment as a source reports it. A nil start is the file's start, a nil end its end.
struct SkipSegmentSpan: Equatable, Sendable {
    let start: TimeInterval?
    let end: TimeInterval?

    init(start: TimeInterval?, end: TimeInterval?) {
        self.start = start
        self.end = end
    }

    init(startMS: Double?, endMS: Double?) {
        start = startMS.map { $0 / 1000 }
        end = endMS.map { $0 / 1000 }
    }
}
