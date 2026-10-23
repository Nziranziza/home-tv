import Foundation
import Observation

/// Shows and auto-hides the transport bar. The bar stays up while paused or held, and hides after
/// `hideDelay` of playback without remote input.
@Observable
@MainActor
final class PlayerBarController {
    private(set) var isVisible = false
    @ObservationIgnored private let hideDelay: Duration
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    /// Set while a menu is open over the bar.
    @ObservationIgnored private var isHeld = false

    init(hideDelay: Duration = .seconds(5)) {
        self.hideDelay = hideDelay
    }

    /// Shows the bar, or keeps it up, and restarts the hide countdown when playing.
    func show(isPlaying: Bool) {
        isVisible = true
        scheduleHide(isPlaying: isPlaying)
    }

    /// Keeps the bar up until `release`, whatever playback does.
    func hold() {
        isHeld = true
        show(isPlaying: false)
    }

    func release(isPlaying: Bool) {
        isHeld = false
        show(isPlaying: isPlaying)
    }

    func hide() {
        isHeld = false
        hideTask?.cancel()
        hideTask = nil
        isVisible = false
    }

    /// Remote input or a playback change while the bar is up.
    func noteActivity(isPlaying: Bool) {
        guard isVisible else { return }
        scheduleHide(isPlaying: isPlaying)
    }

    private func scheduleHide(isPlaying: Bool) {
        hideTask?.cancel()
        hideTask = nil
        guard isPlaying, !isHeld else { return }
        let delay = hideDelay
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.isVisible = false
        }
    }
}
