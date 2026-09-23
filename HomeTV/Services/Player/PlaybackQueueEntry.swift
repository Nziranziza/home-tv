import Foundation

/// One item in a hand-off to an external player. `filename` is not a display string — see
/// `PlayerFilename`.
struct PlaybackQueueEntry: Hashable, Sendable, Identifiable {
    /// Stremio episode id, e.g. `tt0903747:1:4`.
    let episodeID: String
    let season: Int
    let episode: Int
    let url: URL
    let filename: String
    /// Episode runtime, for turning the position the player reports back into a resume fraction.
    var runtimeSeconds: Int? = nil

    var id: String { episodeID }
}
