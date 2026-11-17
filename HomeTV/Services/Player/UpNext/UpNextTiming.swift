import Foundation

/// When Up Next resolves and shows, by the time left in the episode.
enum UpNextTiming {
    /// The next episode's stream is looked up this long before the end.
    static let resolveLead: TimeInterval = 5 * 60
    /// Up Next shows, and the next stream opens, this long before the end.
    static let showLead: TimeInterval = 30
    /// A failed lookup is tried again after this long, up to `maxAttempts` in all.
    static let retryDelay: Duration = .seconds(10)
    static let maxAttempts = 3

    static func isResolveDue(remaining: TimeInterval) -> Bool {
        remaining <= resolveLead
    }

    static func isShowDue(remaining: TimeInterval) -> Bool {
        remaining <= showLead
    }

    /// The countdown's whole seconds, never below zero.
    static func secondsLeft(remaining: TimeInterval) -> Int {
        max(Int(remaining.rounded(.up)), 0)
    }
}
