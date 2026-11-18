import Foundation

/// One source's segments: the file's chapters or a timestamp database.
struct SkipSegmentSource: Equatable, Sendable {
    var spans: [SkipSegment.Kind: [SkipSegmentSpan]] = [:]
    /// Where a scene after the credits starts.
    var postCreditsStart: TimeInterval?
}
