import Foundation
import GameController

/// Reads horizontal swipes on the Siri Remote's click pad. SwiftUI only reports swipes as discrete focus
/// moves, so the paused scrub reads the pad's absolute position through GameController.
@MainActor
final class RemoteSwipeTracker {
    /// Called with each horizontal step, as a fraction of the pad's width, and the swipe's speed in pad
    /// widths per second.
    var onSwipe: ((_ fraction: Double, _ speed: Double) -> Void)?
    /// When the finger last travelled, for the swipe's speed.
    private var lastSwipeAt: ContinuousClock.Instant?
    private var lastX: Float?
    /// Smoothed, so one jittery sample doesn't jump the scrub.
    private var speed: Double = 0
    private var pad: GCMicroGamepad?
    private var connectTask: Task<Void, Never>?

    func start() {
        attach(GCController.current)
        connectTask = Task { [weak self] in
            for await note in NotificationCenter.default.notifications(named: .GCControllerDidBecomeCurrent) {
                let controller = note.object as? GCController
                self?.attach(controller)
            }
        }
    }

    func stop() {
        connectTask?.cancel()
        connectTask = nil
        detach()
        onSwipe = nil
    }

    private func attach(_ controller: GCController?) {
        guard let pad = controller?.microGamepad, pad !== self.pad else { return }
        // The previous remote would otherwise keep scrubbing.
        detach()
        self.pad = pad
        pad.reportsAbsoluteDpadValues = true
        // GameController calls back on the main queue by default.
        pad.dpad.valueChangedHandler = { [weak self] _, x, y in
            MainActor.assumeIsolated { self?.padMoved(x: x, y: y) }
        }
    }

    private func detach() {
        pad?.dpad.valueChangedHandler = nil
        pad = nil
        lastX = nil
    }

    private func padMoved(x: Float, y: Float) {
        // Lifting the finger reports the centre.
        guard x != 0 || y != 0 else {
            lastX = nil
            speed = 0
            return
        }
        defer { lastX = x }
        guard let lastX else { return }
        let step = Double(x - lastX) / 2
        guard abs(step) > 0.002 else { return }
        let now = ContinuousClock.now
        if let lastSwipeAt, now - lastSwipeAt < .milliseconds(100) {
            let interval = max((now - lastSwipeAt) / .seconds(1), 0.004)
            speed = speed * 0.6 + abs(step) / interval * 0.4
        } else {
            speed = 0
        }
        lastSwipeAt = now
        onSwipe?(step, speed)
    }
}
