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
}
