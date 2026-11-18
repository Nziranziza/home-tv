import Foundation
import Observation

/// The intro, recap and credits of what's playing, and the one the Skip button offers. Chapters come
/// first, then TheIntroDB, then IntroDB.app.
@Observable
@MainActor
final class PlayerSkipSegments {
    /// The segment playing now, unless the viewer dismissed it or the setting is off.
    private(set) var active: SkipSegment?
    let isEnabled: Bool

    @ObservationIgnored private var chapters = SkipSegmentSource()
    @ObservationIgnored private var remote: [SkipSegmentSource] = []
    @ObservationIgnored private var resolved: (duration: TimeInterval, segments: [SkipSegment])?
    /// Dismissed with Menu or skipped; stays hidden until playback goes back before its start. Moving past
    /// its end doesn't count, as a seek out can land back inside on a keyframe.
    @ObservationIgnored private var dismissed: SkipSegment?
    @ObservationIgnored private(set) var loadTask: Task<Void, Never>?
    @ObservationIgnored private let fetch: @MainActor (SkipSegmentQuery) async -> [SkipSegmentSource]

    init(isEnabled: Bool, fetch: @escaping @MainActor (SkipSegmentQuery) async -> [SkipSegmentSource]) {
        self.isEnabled = isEnabled
        self.fetch = fetch
    }

    /// Starts the databases' lookup once.
    func load(_ query: SkipSegmentQuery?) {
        guard loadTask == nil, let query else { return }
        loadTask = Task { [weak self, fetch] in
            let sources = await fetch(query)
            guard !Task.isCancelled, let self else { return }
            remote = sources
            resolved = nil
        }
    }

    func chaptersDidLoad(_ chapters: [PlaybackChapter]) {
        self.chapters = ChapterSegmentMatcher.source(from: chapters)
        resolved = nil
    }

    /// The segments, checked against `duration`.
    func segments(duration: TimeInterval) -> [SkipSegment] {
        if let resolved, resolved.duration == duration { return resolved.segments }
        let segments = SkipSegmentResolver.segments(from: [chapters] + remote, duration: duration)
        resolved = (duration, segments)
        return segments
    }

    func credits(duration: TimeInterval) -> SkipSegment? {
        segments(duration: duration).first { $0.kind == .credits }
    }

    /// Moves `active` to the segment at `time`.
    func update(time: TimeInterval, duration: TimeInterval) {
        let current = SkipSegmentResolver.active(in: segments(duration: duration), at: time)
        if let dismissed, time < dismissed.start { self.dismissed = nil }
        let shown = isEnabled && current != dismissed ? current : nil
        if active != shown { active = shown }
    }

    /// Hides the button until playback goes back before the segment.
    func dismiss() {
        dismissed = active
        active = nil
    }

    func cancel() {
        loadTask?.cancel()
    }
}
