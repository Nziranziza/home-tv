import Foundation
import Testing
@testable import HomeTV

/// Picking each channel card's key art.
@MainActor
struct ExploreChannelsModelTests {
    private let lawAndOrder = URL(string: "https://x/law.jpg")!
    private let dahmer = URL(string: "https://x/dahmer.jpg")!
    private let mentalist = URL(string: "https://x/mentalist.jpg")!

    @Test func aLaterChannelSkipsAPosterAnEarlierOneShows() {
        let art = ExploreChannelsModel.assignArtwork(
            channels: [8, 15],
            candidates: [8: [lawAndOrder, dahmer], 15: [lawAndOrder, mentalist]]
        )
        #expect(art[8] == lawAndOrder)
        #expect(art[15] == mentalist)
    }

    @Test func aChannelWhoseCandidatesAreAllTakenKeepsItsTopPoster() {
        let art = ExploreChannelsModel.assignArtwork(
            channels: [8, 15],
            candidates: [8: [lawAndOrder], 15: [lawAndOrder]]
        )
        #expect(art[15] == lawAndOrder)
    }

    @Test func rowOrderDecidesWhoKeepsASharedPoster() {
        let art = ExploreChannelsModel.assignArtwork(
            channels: [15, 8],
            candidates: [8: [lawAndOrder, dahmer], 15: [lawAndOrder, mentalist]]
        )
        #expect(art[15] == lawAndOrder)
        #expect(art[8] == dahmer)
    }
}
