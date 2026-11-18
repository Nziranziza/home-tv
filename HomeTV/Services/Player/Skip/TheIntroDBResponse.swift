import Foundation

/// TheIntroDB's `/v4/media`. Kinds with no segments are left out.
struct TheIntroDBResponse: Decodable, Sendable {
    struct Segment: Decodable, Sendable {
        let startMs: Double?
        let endMs: Double?
    }

    let intro: [Segment]?
    let recap: [Segment]?
    let credits: [Segment]?

    var source: SkipSegmentSource {
        let spans: [SkipSegment.Kind: [Segment]?] = [.intro: intro, .recap: recap, .credits: credits]
        return SkipSegmentSource(spans: spans.compactMapValues { segments in
            segments?.map { SkipSegmentSpan(startMS: $0.startMs, endMS: $0.endMs) }
        })
    }
}
