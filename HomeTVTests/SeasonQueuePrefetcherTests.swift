import Foundation
import Testing
@testable import HomeTV

/// The launch-time wait. Its failure mode is silent: a wait that can never be satisfied costs every
/// launch the full deadline and returns nothing better than it started with.
@MainActor
struct SeasonQueuePrefetcherTests {

    @Test func anEpisodeThatWasNeverScheduledIsNeverResolved() {
        let prefetcher = SeasonQueuePrefetcher()
        #expect(prefetcher.hasResolved(["tt0944947:1:2"]) == false)
    }

    @Test func nothingToWaitForReturnsAtOnce() async {
        // No add-ons, so no request is ever scheduled and the wait has nothing to satisfy it.
        let prefetcher = SeasonQueuePrefetcher()
        prefetcher.start(type: "series", episodeIDs: ["tt0944947:1:2"], addons: [])

        let started = ContinuousClock.now
        await prefetcher.awaitResolution(of: ["tt0944947:1:2"], within: .seconds(5))
        #expect(started.duration(to: .now) < .milliseconds(500))
    }

    @Test func cancellingEndsAWaitRatherThanLettingItRunOut() async {
        let prefetcher = SeasonQueuePrefetcher()
        prefetcher.cancel()

        let started = ContinuousClock.now
        await prefetcher.awaitResolution(of: ["tt0944947:1:2"], within: .seconds(5))
        #expect(started.duration(to: .now) < .milliseconds(500))
    }

    @Test func aReplacedPrefetchDoesNotEndItsSuccessorsWait() async {
        // Cancelling does not wait for the old driver, so its completion must not be mistaken for the
        // new one's — that would cut the wait short and shorten the queue.
        let prefetcher = SeasonQueuePrefetcher()
        prefetcher.start(type: "series", episodeIDs: ["tt0944947:1:2"], addons: [])
        prefetcher.start(type: "series", episodeIDs: ["tt0944947:2:2"], addons: [])
        #expect(prefetcher.hasResolved(["tt0944947:2:2"]) == false)
    }

    @Test func anEmptyRequestIsNotWaitedOn() async {
        let prefetcher = SeasonQueuePrefetcher()
        let started = ContinuousClock.now
        await prefetcher.awaitResolution(of: [], within: .seconds(5))
        #expect(started.duration(to: .now) < .milliseconds(500))
    }
}
