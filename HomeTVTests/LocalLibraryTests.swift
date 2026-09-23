import Foundation
import Testing
@testable import HomeTV

/// The on-device library — watched marks, resume points and the watchlist — which is what HomeTV uses
/// when Trakt is not connected, and the only place an episode played inside Infuse can be recorded.
@MainActor
struct LocalLibraryTests {

    /// A store on its own defaults suite, so tests never touch the app's real library.
    static func makeStore(_ suite: String = UUID().uuidString) -> LocalLibrary {
        LocalLibrary(defaults: UserDefaults(suiteName: suite) ?? .standard)
    }

    static func preview(_ id: String, _ name: String) -> MetaPreview {
        .placeholder(type: "movie", id: id, name: name)
    }

    // MARK: - Ids

    @Test func idsAreStremioContentIDs() {
        #expect(LocalLibrary.id(show: "tt0903747") == "tt0903747")
        #expect(LocalLibrary.id(show: "tt0903747", season: 1, episode: 4) == "tt0903747:1:4")
        // Coercing a missing number to 0 would write a record no read ever matches.
        #expect(LocalLibrary.id(show: "tt0903747", season: 1, episode: nil) == nil)
        #expect(LocalLibrary.id(show: "", season: 1, episode: 4) == nil)
    }

    // MARK: - Watched

    @Test func watchedIsTrackedPerEpisodeAndPerTitle() {
        let store = Self.makeStore()
        store.setWatched(true, id: "tt0903747:1:4")
        #expect(store.isWatched("tt0903747:1:4"))
        #expect(store.isWatched("tt0903747:1:5") == false)
        #expect(store.isWatched("tt0903747") == false)
    }

    @Test func finishingSomethingClearsItsResumePoint() {
        let store = Self.makeStore()
        store.setProgress(0.4, id: "tt1375666")
        store.setWatched(true, id: "tt1375666")
        #expect(store.progress(forKey: "tt1375666") == nil)
    }

    @Test func togglingFlipsBothWays() {
        let store = Self.makeStore()
        store.toggleWatched(id: "tt1375666")
        #expect(store.isWatched("tt1375666"))
        store.toggleWatched(id: "tt1375666")
        #expect(store.isWatched("tt1375666") == false)
    }

    // MARK: - Progress

    @Test func aResumePointIsKeptOnlyInsideTheResumeWindow() {
        let store = Self.makeStore()
        // Barely started, and all but finished: neither is something to continue.
        store.setProgress(0.002, id: "a")
        store.setProgress(0.99, id: "b")
        store.setProgress(0.4, id: "c")
        #expect(store.progress(forKey: "a") == nil)
        #expect(store.progress(forKey: "b") == nil)
        #expect(store.progress(forKey: "c") == 0.4)
    }

    @Test func playingOnPastTheWindowDropsAnExistingResumePoint() {
        let store = Self.makeStore()
        store.setProgress(0.4, id: "c")
        store.setProgress(0.99, id: "c")
        #expect(store.progress(forKey: "c") == nil)
    }

    // MARK: - Watchlist

    @Test func theWatchlistTogglesAndKeepsNewestFirst() {
        let store = Self.makeStore()
        store.toggleWatchlist(Self.preview("tt1", "One"))
        store.toggleWatchlist(Self.preview("tt2", "Two"))
        #expect(store.watchlist.map(\.id) == ["tt2", "tt1"])
        #expect(store.isInWatchlist("tt1"))
        store.toggleWatchlist(Self.preview("tt1", "One"))
        #expect(store.isInWatchlist("tt1") == false)
        #expect(store.watchlist.map(\.id) == ["tt2"])
    }

    // MARK: - Persistence

    @Test func everythingSurvivesARelaunch() {
        let suite = UUID().uuidString
        let store = Self.makeStore(suite)
        store.setWatched(true, id: "tt0903747:1:4")
        store.setProgress(0.3, id: "tt0903747:1:5")
        store.toggleWatchlist(Self.preview("tt1375666", "Inception"))

        // A second store over the same defaults stands in for the next launch.
        let reloaded = Self.makeStore(suite)
        #expect(reloaded.isWatched("tt0903747:1:4"))
        #expect(reloaded.progress(forKey: "tt0903747:1:5") == 0.3)
        #expect(reloaded.watchlist.map(\.name) == ["Inception"])
    }
}
