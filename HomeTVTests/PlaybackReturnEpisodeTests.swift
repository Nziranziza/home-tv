import Testing
@testable import HomeTV

/// Which episode a player handed back, read from its content id.
@MainActor
struct PlaybackReturnEpisodeTests {
    @Test func episodeIDsYieldTheirNumbers() {
        let numbers = PlaybackReturnCoordinator.episodeNumbers(in: "tt0903747:2:5")
        #expect(numbers?.season == 2)
        #expect(numbers?.episode == 5)
    }

    @Test func moviesAndShowsHaveNoEpisode() {
        #expect(PlaybackReturnCoordinator.episodeNumbers(in: "tt0903747") == nil)
        #expect(PlaybackReturnCoordinator.episodeNumbers(in: "tt0903747:x:5") == nil)
    }

    @Test func givenEpisodeNumbersWinOverTheID() {
        let item = PlaybackItem(contentID: "kitsu:1234:5", showID: "kitsu:1234", season: 1, episode: 5)
        #expect(item.season == 1)
        #expect(item.episode == 5)
        let parsed = PlaybackItem(contentID: "tt0903747:2:5", showID: "tt0903747")
        #expect(parsed.season == 2)
        #expect(parsed.episode == 5)
        let movie = PlaybackItem(contentID: "tt1375666", showID: "tt1375666")
        #expect(movie.season == nil)
    }
}
