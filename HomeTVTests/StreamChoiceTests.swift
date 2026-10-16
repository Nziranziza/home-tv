import Foundation
import Testing
@testable import HomeTV

/// Matching a saved stream identity against a freshly fetched stream list, as Continue Watching does.
struct StreamChoiceTests {

    static let movie = "tt1375666"
    static let episode1 = "tt0903747:1:1"
    static let episode2 = "tt0903747:1:2"
    static let addon = "com.torrentio"

    static func stream(
        title: String = "Show.S01E01.1080p.WEB-DL-GROUP\n👤 42 💾 2.1 GB",
        name: String = "[RD+] Torrentio\n1080p",
        url: String? = "https://debrid.example/a1b2/file.mkv",
        hash: String? = nil,
        fileIdx: Int? = nil,
        binge: String? = nil,
        filename: String? = nil
    ) -> HomeTV.Stream {
        HomeTV.Stream(
            name: name,
            title: title,
            description: nil,
            url: url,
            ytId: nil,
            infoHash: hash,
            fileIdx: fileIdx,
            sources: nil,
            behaviorHints: (binge != nil || filename != nil)
                ? StreamBehaviorHints(bingeGroup: binge, notWebReady: nil, proxyHeaders: nil, filename: filename)
                : nil
        )
    }

    static func candidates(_ streams: HomeTV.Stream..., addon: String = addon) -> [SeasonQueueBuilder.Candidate] {
        streams.map { .init(stream: $0, addonID: addon) }
    }

    // MARK: - Same title

    @Test func sameFileMatchesByFilenameAfterTheURLChanged() {
        let saved = StreamChoice(
            stream: Self.stream(url: "https://debrid.example/old/file.mkv", filename: "Show.S01E01.mkv"),
            addonID: Self.addon,
            contentID: Self.episode1
        )
        let other = Self.stream(title: "Show.S01E01.720p", url: "https://debrid.example/new/720.mkv", filename: "Show.S01E01.720p.mkv")
        let wanted = Self.stream(url: "https://debrid.example/new/file.mkv", filename: "Show.S01E01.mkv")

        let match = saved.match(for: Self.episode1, among: Self.candidates(other, wanted))
        #expect(match == wanted)
    }

    @Test func sameFileMatchesByInfoHashAndFileIndex() {
        let saved = StreamChoice(
            stream: Self.stream(url: nil, hash: "ABCDEF", fileIdx: 3),
            addonID: Self.addon,
            contentID: Self.movie
        )
        let otherFile = Self.stream(url: nil, hash: "abcdef", fileIdx: 1)
        let wanted = Self.stream(url: nil, hash: "abcdef", fileIdx: 3)

        #expect(saved.match(for: Self.movie, among: Self.candidates(otherFile, wanted)) == wanted)
    }

    @Test func sameFileMatchesByReleaseNameWhenSeedersAndCacheTagChanged() {
        let saved = StreamChoice(
            stream: Self.stream(name: "[RD download] Torrentio"),
            addonID: Self.addon,
            contentID: Self.episode1
        )
        let other = Self.stream(title: "Show.S01E01.2160p.WEB-DL-OTHER\n👤 9")
        let wanted = Self.stream(title: "Show.S01E01.1080p.WEB-DL-GROUP\n👤 87 💾 2.1 GB", url: "https://debrid.example/zz/file.mkv")

        #expect(saved.match(for: Self.episode1, among: Self.candidates(other, wanted)) == wanted)
    }

    @Test func sameFileSkipsADebridLinkThatIsNoLongerCached() {
        let saved = StreamChoice(stream: Self.stream(filename: "Show.S01E01.mkv"), addonID: Self.addon, contentID: Self.episode1)
        let uncached = Self.stream(name: "[RD download] Torrentio", filename: "Show.S01E01.mkv")

        #expect(saved.match(for: Self.episode1, among: Self.candidates(uncached)) == nil)
    }

    @Test func aSharedDisplayNameIsNotAFileMatch() {
        // No title: the release name would only be the add-on's display name, shared by every link.
        let saved = StreamChoice(
            stream: HomeTV.Stream(
                name: "Direct", title: nil, description: "1080p WEB", url: "https://cdn.example/a.mp4",
                ytId: nil, infoHash: nil, fileIdx: nil, sources: nil, behaviorHints: nil
            ),
            addonID: Self.addon,
            contentID: Self.movie
        )
        let otherLink = HomeTV.Stream(
            name: "Direct", title: nil, description: "480p CAM", url: "https://cdn.example/b.mp4",
            ytId: nil, infoHash: nil, fileIdx: nil, sources: nil, behaviorHints: nil
        )

        #expect(saved.releaseName == nil)
        #expect(saved.match(for: Self.movie, among: Self.candidates(otherLink)) == nil)
    }

    @Test func sameReleaseNameWithADifferentFilenameIsNotAMatch() {
        let saved = StreamChoice(stream: Self.stream(filename: "Show.S01E01.mkv"), addonID: Self.addon, contentID: Self.episode1)
        let otherFile = Self.stream(filename: "Show.S01E01.sample.mkv")

        #expect(saved.match(for: Self.episode1, among: Self.candidates(otherFile)) == nil)
    }

    @Test func anotherAddonsIdenticalStreamDoesNotMatch() {
        let saved = StreamChoice(stream: Self.stream(), addonID: Self.addon, contentID: Self.episode1)
        let elsewhere = Self.candidates(Self.stream(), addon: "com.comet")

        #expect(saved.match(for: Self.episode1, among: elsewhere) == nil)
    }

    @Test func noMatchingStreamReturnsNil() {
        let saved = StreamChoice(stream: Self.stream(filename: "a.mkv"), addonID: Self.addon, contentID: Self.movie)
        let unrelated = Self.stream(title: "Other.Movie.2160p", filename: "b.mkv")

        #expect(saved.match(for: Self.movie, among: Self.candidates(unrelated)) == nil)
        #expect(saved.match(for: Self.movie, among: []) == nil)
    }

    // MARK: - Next episode

    @Test func nextEpisodeContinuesTheSameReleaseByBingeGroup() {
        let saved = StreamChoice(
            stream: Self.stream(binge: "torrentio|1080p|GROUP", filename: "Show.S01E01.mkv"),
            addonID: Self.addon,
            contentID: Self.episode1
        )
        let otherRelease = Self.stream(title: "Show.S01E02.2160p", binge: "torrentio|4k|OTHER")
        let sameRelease = Self.stream(
            title: "Show.S01E02.1080p.WEB-DL-GROUP",
            url: "https://debrid.example/e2.mkv",
            binge: "torrentio|1080p|GROUP",
            filename: "Show.S01E02.mkv"
        )

        #expect(saved.match(for: Self.episode2, among: Self.candidates(otherRelease, sameRelease)) == sameRelease)
    }

    @Test func nextEpisodeIgnoresAMatchingReleaseNameWithoutAnIdentity() {
        // The literal release line differs per episode, and nothing weaker than an identity is trusted.
        let saved = StreamChoice(stream: Self.stream(), addonID: Self.addon, contentID: Self.episode1)
        let next = Self.stream(title: "Show.S01E02.1080p.WEB-DL-GROUP")

        #expect(saved.match(for: Self.episode2, among: Self.candidates(next)) == nil)
    }

    @Test func nextEpisodeRejectsAnUncachedDebridStream() {
        let saved = StreamChoice(stream: Self.stream(binge: "pack"), addonID: Self.addon, contentID: Self.episode1)
        let uncached = Self.stream(title: "Show.S01E02", name: "[RD download] Torrentio", binge: "pack")

        #expect(saved.match(for: Self.episode2, among: Self.candidates(uncached)) == nil)
    }

    // MARK: - Store

    @MainActor
    @Test func storeRoundTripsAChoicePerTitle() throws {
        let suite = "StreamChoiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let choice = StreamChoice(stream: Self.stream(binge: "pack"), addonID: Self.addon, contentID: Self.episode1)

        StreamChoiceStore(defaults: defaults).record(choice, forTitle: "tt0903747")

        let reloaded = StreamChoiceStore(defaults: defaults)
        #expect(reloaded.choice(forTitle: "tt0903747") == choice)
        #expect(reloaded.choice(forTitle: Self.movie) == nil)
    }
}
