import Foundation
import Observation

/// Shows and auto-hides the transport bar. The bar stays up while paused and hides after `hideDelay` of
/// playback without remote input.
@Observable
@MainActor
final class PlayerBarController {
    private(set) var isVisible = false
    @ObservationIgnored private let hideDelay: Duration
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    init(hideDelay: Duration = .seconds(5)) {
        self.hideDelay = hideDelay
    }

    /// Shows the bar, or keeps it up, and restarts the hide countdown when playing.
    func show(isPlaying: Bool) {
        isVisible = true
        scheduleHide(isPlaying: isPlaying)
    }

    func hide() {
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
        guard isPlaying else { return }
        let delay = hideDelay
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.isVisible = false
        }
    }
}
