import Foundation

/// A seek the viewer is still choosing: a scan or a swipe away from where playback was. The engine stays
/// paused at `origin` until it's committed or cancelled.
struct PlayerScrub: Equatable {
    /// Where playback was when the scrub began; a cancel returns here.
    let origin: TimeInterval
    /// Playback was running when it began: the fill follows the scrub, and one Menu cancels it.
    let isFromPlayback: Bool
    let duration: TimeInterval
    private(set) var scan: PlayerScan?
    /// The position at `anchorTime`; a scan moves on from it at its rate.
    private var anchor: TimeInterval
    private var anchorTime: ContinuousClock.Instant

    init(
        origin: TimeInterval,
        duration: TimeInterval,
        isFromPlayback: Bool,
        scan: PlayerScan? = nil,
        at now: ContinuousClock.Instant
    ) {
        self.origin = origin
        self.duration = duration
        self.isFromPlayback = isFromPlayback
        self.scan = scan
        anchor = origin
        anchorTime = now
    }

    /// Stops at either end of the title.
    func position(at now: ContinuousClock.Instant) -> TimeInterval {
        guard let scan else { return anchor }
        let elapsed = now - anchorTime
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        return clamped(anchor + scan.rate * seconds)
    }

    mutating func move(to position: TimeInterval, at now: ContinuousClock.Instant) {
        anchor = clamped(position)
        anchorTime = now
    }

    mutating func startScan(_ direction: PlayerScan.Direction, at now: ContinuousClock.Instant) {
        reanchor(at: now)
        scan = PlayerScan(direction: direction)
    }

    mutating func click(_ side: PlayerScan.Direction, at now: ContinuousClock.Instant) {
        reanchor(at: now)
        scan?.click(side)
    }

    /// Holds the position where the scan has reached.
    mutating func stopScan(at now: ContinuousClock.Instant) {
        reanchor(at: now)
        scan = nil
    }

    private mutating func reanchor(at now: ContinuousClock.Instant) {
        anchor = position(at: now)
        anchorTime = now
    }

    private func clamped(_ time: TimeInterval) -> TimeInterval {
        min(max(0, time), duration)
    }
}
