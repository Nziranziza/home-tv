import AVKit
import UIKit

/// The TV mode switch Match Content makes for a stream. Reports its blackout so playback can wait it
/// out, and hands the TV back to its default mode when the player closes.
@MainActor
final class DisplayModeSwitch {
    var onStart: (() -> Void)?
    var onEnd: (() -> Void)?

    private var observers: [Task<Void, Never>] = []

    /// True while the TV is blacked out changing mode.
    var isInProgress: Bool { Self.manager?.isDisplayModeSwitchInProgress ?? false }

    /// Only one window on tvOS, and its manager drives the whole display.
    private static var manager: AVDisplayManager? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first }
            .first?.avDisplayManager
    }

    func startObserving() {
        guard observers.isEmpty else { return }
        observers = [
            observe(.AVDisplayManagerModeSwitchStart) { $0.onStart?() },
            observe(.AVDisplayManagerModeSwitchEnd) { $0.onEnd?() },
        ]
    }

    /// Stops observing and drops the stream's mode, which switches the TV back if one was applied.
    func reset() {
        observers.forEach { $0.cancel() }
        observers = []
        Self.manager?.preferredDisplayCriteria = nil
    }

    private func observe(_ name: Notification.Name, _ handler: @escaping (DisplayModeSwitch) -> Void) -> Task<Void, Never> {
        // Subscribed now, not when the task first runs, so a switch ending in between isn't missed.
        let notifications = NotificationCenter.default.notifications(named: name).map { _ in }
        return Task { [weak self] in
            for await _ in notifications {
                guard let self else { return }
                handler(self)
            }
        }
    }
}
