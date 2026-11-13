/// Debug-only player logging. `print`, because `devicectl --console` shows stdout but not `Logger`.
enum PlaybackDiagnostics {
    #if DEBUG
    private static let origin = ContinuousClock.now
    @MainActor private static var selectedAt: ContinuousClock.Instant?
    #endif

    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        let ms = (ContinuousClock.now - origin).components.seconds * 1000
            + (ContinuousClock.now - origin).components.attoseconds / 1_000_000_000_000_000
        print("[Player] \(ms)ms \(message())")
        #endif
    }

    /// Select (or a debug launch): the start of the time-to-first-frame measurement.
    @MainActor static func markSelect() {
        #if DEBUG
        selectedAt = .now
        log("select")
        #endif
    }

    @MainActor static func firstFrame(route: String) {
        #if DEBUG
        guard let selectedAt else { return }
        let elapsed = ContinuousClock.now - selectedAt
        self.selectedAt = nil
        log("first frame on \(route) after \(elapsed.formatted(.units(allowed: [.milliseconds])))")
        #endif
    }
}
