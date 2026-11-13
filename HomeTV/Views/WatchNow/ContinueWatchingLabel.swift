import Foundation

/// The text beside a Continue Watching card's progress bar: `S1, E2 · 15m`, or `2h 9m` for a movie.
@MainActor
enum ContinueWatchingLabel {
    /// The real label, or nil when nothing is known about the title's progress.
    nonisolated static func text(season: Int?, episode: Int?, secondsLeft: Int?, fraction: Double?) -> String? {
        let timeLeft = secondsLeft.map(timeText)
        if let season, let episode {
            let numbers = "S\(season), E\(episode)"
            return timeLeft.map { "\(numbers) · \($0)" } ?? numbers
        }
        if let timeLeft { return timeLeft }
        return fraction.map { "\(Int(($0 * 100).rounded()))% watched" }
    }

    /// Seconds left in `key`'s title, when a player saved an exact position for it.
    static func secondsLeft(forKey key: String) -> Int? {
        guard let position = UserLibrary.resumeSeconds(forKey: key),
              let fraction = UserLibrary.progress(forKey: key), fraction > 0 else { return nil }
        return max(0, Int((Double(position) / fraction).rounded()) - position)
    }

    /// Whole minutes, at least one: `15m`, `2h 9m`.
    nonisolated static func timeText(seconds: Int) -> String {
        let minutes = max(1, Int((Double(seconds) / 60).rounded()))
        return Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }
}
