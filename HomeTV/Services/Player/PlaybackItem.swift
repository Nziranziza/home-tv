/// The title a play belongs to, for saving where it got to.
struct PlaybackItem: Equatable, Sendable {
    /// Stremio content id of what's playing: `tt0903747` or `tt0903747:1:4`.
    let contentID: String
    /// The show (or the movie itself), which Continue Watching cards are keyed by.
    let showID: String
    /// Episode numbers, nil for a movie. Kept apart from the id: some add-ons' ids don't spell them out.
    let season: Int?
    let episode: Int?

    /// Numbers not given are read from `contentID`.
    init(contentID: String, showID: String, season: Int? = nil, episode: Int? = nil) {
        let parsed = PlaybackReturnCoordinator.episodeNumbers(in: contentID)
        self.contentID = contentID
        self.showID = showID
        self.season = season ?? parsed?.season
        self.episode = episode ?? parsed?.episode
    }
}
