import Foundation

/// IntroDB.app's `/segments`. A kind with no data is null.
struct IntroDBAppResponse: Decodable, Sendable {
    struct Segment: Decodable, Sendable {
        let startMs: Double?
        let endMs: Double?

        var span: SkipSegmentSpan { SkipSegmentSpan(startMS: startMs, endMS: endMs) }
    }

    let intro: Segment?
    let recap: Segment?
    let outro: Segment?
    let postCredits: Segment?

    var source: SkipSegmentSource {
        let spans: [SkipSegment.Kind: Segment?] = [.intro: intro, .recap: recap, .credits: outro]
        return SkipSegmentSource(
            spans: spans.compactMapValues { $0.map { [$0.span] } },
            postCreditsStart: postCredits?.startMs.map { $0 / 1000 }
        )
    }
}
