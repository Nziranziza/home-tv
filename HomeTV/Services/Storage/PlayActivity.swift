import Foundation

/// An episode's newest play activity: when it was last paused or finished, and which of the two.
struct PlayActivity: Codable, Equatable, Sendable {
    let date: Date
    let isFinished: Bool

    /// The newer of two activities; `a` wins a tie.
    static func newest(_ a: PlayActivity?, _ b: PlayActivity?) -> PlayActivity? {
        guard let a else { return b }
        guard let b, b.date > a.date else { return a }
        return b
    }
}
