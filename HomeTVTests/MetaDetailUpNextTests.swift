import Foundation
import Testing
@testable import HomeTV

/// The show hero's up-next episode: only the last played episode decides it (#68).
struct MetaDetailUpNextTests {

    // MARK: - Last played episode

    /// 1. Finished E1–E5 → paused E2.
    @Test func unfinishedLastPlayedResumes() {
        let next = upNext(watched: 1...5, timeline: [.binge(1...5), .paused(2)], progress: [2: 0.4])
        #expect(next?.video.episode == 2)
        #expect(next?.label == "Resume S1, E2")
        #expect(next?.resumeProgress == 0.4)
        #expect(next?.marksEpisode == true)
        #expect(next?.describesEpisode == true)
    }

    /// 2. Finished E1–E5 → finished E2.
    @Test func completedLastPlayedPlaysTheNextEpisodeNotTheFurthest() {
        let next = upNext(watched: 1...5, timeline: [.binge(1...5), .finished(2)])
        #expect(next?.video.episode == 3)
        #expect(next?.label == "Play S1, E3")
        #expect(next?.resumeProgress == nil)
        #expect(next?.marksEpisode == true)
        #expect(next?.describesEpisode == true)
    }

    /// 3. Finished E1–E6 → paused E7 → paused E2.
    @Test func unfinishedLastPlayedWinsOverALaterEpisodeWithProgress() {
        let next = upNext(
            watched: 1...6,
            timeline: [.binge(1...6), .paused(7), .paused(2)],
            progress: [7: 0.5, 2: 0.2]
        )
        #expect(next?.label == "Resume S1, E2")
        #expect(next?.resumeProgress == 0.2)
    }

    /// 4. Finished E1–E6 → paused E7 → paused E4 → finished E2.
    @Test func completedLastPlayedIgnoresOtherUnfinishedEpisodes() {
        let next = upNext(
            watched: 1...6,
            timeline: [.binge(1...6), .paused(7), .paused(4), .finished(2)],
            progress: [7: 0.5, 4: 0.3]
        )
        #expect(next?.label == "Play S1, E3")
    }

    /// 5. Finished E1–E6 → paused E2 → paused E7.
    @Test func unfinishedLastPlayedLaterInTheShowResumes() {
        let next = upNext(
            watched: 1...6,
            timeline: [.binge(1...6), .paused(2), .paused(7)],
            progress: [2: 0.2, 7: 0.5]
        )
        #expect(next?.label == "Resume S1, E7")
    }

    /// 6. Finished E1–E5 → paused E7 → finished E6: the next episode already has progress.
    @Test func nextEpisodeWithProgressResumes() {
        let next = upNext(
            watched: 1...6,
            timeline: [.binge(1...5), .paused(7), .finished(6)],
            progress: [7: 0.5]
        )
        #expect(next?.label == "Resume S1, E7")
        #expect(next?.resumeProgress == 0.5)
    }

    /// 7. Finished E1–E9 → finished E10 (finale).
    @Test func completedFinaleRewatchesFromTheStart() {
        let next = upNext(watched: 1...10, timeline: [.binge(1...9), .finished(10)])
        #expect(next?.video.episode == 1)
        #expect(next?.label == "Rewatch")
        #expect(next?.marksEpisode == false)
        #expect(next?.describesEpisode == false)
    }

    @Test func nextEpisodeCrossesIntoTheNextSeason() {
        let eps = Self.episodes(season: 1, 1...3) + Self.episodes(season: 2, 1...3)
        let next = Self.viewModel.upNext(
            episodes: eps,
            progress: { _ in nil },
            isWatched: { $0.season == 1 },
            lastPlayed: { $0.season == 1 && $0.episode == 3 ? PlayActivity(date: .now, isFinished: true) : nil }
        )
        #expect(next?.label == "Play S2, E1")
    }

    // MARK: - No timestamps: furthest watched

    @Test func withoutActivityResumesTheLatestInProgressEpisode() {
        let next = upNext(watched: 1...6, progress: [2: 0.2, 7: 0.5])
        #expect(next?.label == "Resume S1, E7")
    }

    @Test func withoutActivityPlaysAfterTheFurthestWatched() {
        let next = upNext(watched: [1, 2, 5])
        #expect(next?.label == "Play S1, E6")
    }

    @Test func withoutActivityAfterTheFinaleRewatches() {
        let next = upNext(watched: [10])
        #expect(next?.label == "Rewatch")
        #expect(next?.marksEpisode == false)
    }

    @Test func nothingWatchedPlaysTheFirstEpisode() {
        let next = upNext(watched: [])
        #expect(next?.video.episode == 1)
        #expect(next?.label == "Play First Episode")
        #expect(next?.marksEpisode == true)
        // An untouched show keeps its logline.
        #expect(next?.describesEpisode == false)
    }

    @Test func moviesHaveNoUpNext() {
        let movie = MetaDetailViewModel(
            meta: nil, enrichment: nil, related: [], typeID: "movie", metaID: "tt1", fallbackTitle: "Sample"
        )
        #expect(movie.upNext(episodes: Self.episodes(season: 1, 1...3), progress: { _ in nil },
                             isWatched: { _ in false }, lastPlayed: { _ in nil }) == nil)
    }

    // MARK: - Time left

    @Test func timeLeftIsWhatRemainsOfTheRuntime() {
        #expect(Self.viewModel.timeLeftText(progress: 0.25, runtimeMinutes: 57) == "43m")
        #expect(Self.viewModel.timeLeftText(progress: 0.1, runtimeMinutes: 80) == "1h 12m")
    }

    @Test func timeLeftNeverReadsZeroAndNeedsARuntime() {
        #expect(Self.viewModel.timeLeftText(progress: 0.999, runtimeMinutes: 40) == "1m")
        #expect(Self.viewModel.timeLeftText(progress: 0.5, runtimeMinutes: nil) == nil)
        #expect(Self.viewModel.timeLeftText(progress: 0.5, runtimeMinutes: 0) == nil)
    }

    // MARK: - Runtime

    @Test func addonMinuteRuntimesAreRead() {
        #expect(MetaDetailViewModel.addonMinutes("53 min") == 53)
        #expect(MetaDetailViewModel.addonMinutes("45 mins") == 45)
    }

    @Test func otherAddonRuntimesAreLeftAsGiven() {
        #expect(MetaDetailViewModel.addonMinutes("2 h") == nil)
        #expect(MetaDetailViewModel.addonMinutes("1 hr 30 min") == nil)
        #expect(MetaDetailViewModel.addonMinutes(nil) == nil)
    }

    @Test func implausibleAddonRuntimesAreRejected() {
        #expect(MetaDetailViewModel.addonMinutes("999999999999999999 min") == nil)
        #expect(MetaDetailViewModel.addonMinutes("0 min") == nil)
    }

    // MARK: - Fixtures

    /// One step of play history, oldest first.
    enum Step {
        case finished(Int)
        case paused(Int)
        /// Finished each episode in order.
        case binge(ClosedRange<Int>)
    }

    static let viewModel = MetaDetailViewModel(
        meta: nil, enrichment: nil, related: [], typeID: "series", metaID: "tt1", fallbackTitle: "Sample"
    )

    static func episodes(season: Int, _ numbers: ClosedRange<Int>) -> [Video] {
        numbers.map {
            Video(id: "tt1:\(season):\($0)", name: nil, title: nil, season: season, episode: $0,
                  released: nil, overview: nil, thumbnail: nil)
        }
    }

    /// Up next for a ten-episode season, replaying `timeline` one minute apart.
    private func upNext(
        watched: some Sequence<Int>,
        timeline: [Step] = [],
        progress: [Int: Double] = [:]
    ) -> MetaDetailViewModel.UpNext? {
        let watched = Set(watched)
        var activity: [Int: PlayActivity] = [:]
        var clock = Date(timeIntervalSince1970: 0)
        for step in timeline {
            switch step {
            case .finished(let episode):
                clock += 60
                activity[episode] = PlayActivity(date: clock, isFinished: true)
            case .paused(let episode):
                clock += 60
                activity[episode] = PlayActivity(date: clock, isFinished: false)
            case .binge(let range):
                for episode in range {
                    clock += 60
                    activity[episode] = PlayActivity(date: clock, isFinished: true)
                }
            }
        }
        return Self.viewModel.upNext(
            episodes: Self.episodes(season: 1, 1...10),
            progress: { progress[$0.episode ?? 0] },
            isWatched: { watched.contains($0.episode ?? 0) },
            lastPlayed: { activity[$0.episode ?? 0] }
        )
    }
}
