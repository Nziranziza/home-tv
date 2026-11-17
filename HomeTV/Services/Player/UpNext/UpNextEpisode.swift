import Foundation

/// The episode after the one playing, resolved and ready to play.
struct UpNextEpisode: Sendable {
    let request: PlayerRequest
    let thumbnailURL: URL?
    /// `S1, E2 • Title`.
    let label: String
}
