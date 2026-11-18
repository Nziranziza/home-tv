import Foundation

/// When Up Next resolves and shows, by the time left in the episode.
enum UpNextTiming {
    /// The next episode's stream is looked up this long before the end.
    static let resolveLead: TimeInterval = 5 * 60
    /// Up Next shows, and the next stream opens, this long before the end.
    static let showLead: TimeInterval = 30
    /// Credits starting within this of the end open Up Next; earlier ones are taken as bad data.
    static let creditsWindow: TimeInterval = 10 * 60
    /// A failed lookup is tried again after this long, up to `maxAttempts` in all.
    static let retryDelay: Duration = .seconds(10)
    static let maxAttempts = 3

    /// How long before the end Up Next shows: at the credits when they're known, else `showLead`.
    static func showLead(creditsStart: TimeInterval?, duration: TimeInterval) -> TimeInterval {
        guard let creditsStart, duration > 0 else { return showLead }
        let lead = duration - creditsStart
        return lead > 0 && lead <= creditsWindow ? lead : showLead
    }

    /// The lookup keeps the same head start on Up Next however early it shows.
    static func isResolveDue(remaining: TimeInterval, showLead lead: TimeInterval = showLead) -> Bool {
        remaining <= resolveLead - showLead + lead
    }

    static func isShowDue(remaining: TimeInterval, showLead lead: TimeInterval = showLead) -> Bool {
        remaining <= lead
    }

    /// The countdown's whole seconds, never below zero.
    static func secondsLeft(remaining: TimeInterval) -> Int {
        max(Int(remaining.rounded(.up)), 0)
    }
}
