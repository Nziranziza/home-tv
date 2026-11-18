import Foundation
import Testing
@testable import HomeTV

/// Hand-made SRT files from subtitle add-ons, rebuilt before the player reads them.
struct SubtitleFileRepairTests {
    /// Blocks from a real OpenSubtitles upload (Business Proposal S1E4, REVOLT), with its CRLF endings.
    static let broken = [
        "54", "00:03:45,000 --> 00:03:47,500", "Fine line.", "",
        "55 ", "00:03:49,437 --> 00:03: 52,189 ", "that's why they worked so well together. ", "",
        "00:04:58,673 --> 00:05:01,468", "Trust me. My people don't beat around the bush. ", "",
        "166 ", "- And that's all? - Yes! ", "",
        "14 ", ":40,962 --> 00:14:44,341 ", "If ", "I ", "had a granddaughter like ", "Mrs.", "",
        "300", "00:14:45,000 --> 00:14:46,000", "Next.", "",
    ].joined(separator: "\r\n")

    @Test func aSplitTimestampDropsItsCueInsteadOfStretchingIt() {
        let cues = SubtitleFileRepair.cues(in: Self.broken)
        #expect(cues.map(\.lines) == [
            ["Fine line."],
            ["that's why they worked so well together."],
            ["Trust me. My people don't beat around the bush."],
            ["Next."],
        ])
        #expect(cues[1].start == 229_437)
        #expect(cues[1].end == 232_189)
    }

    @Test func theRepairedFileIsCleanSRT() {
        let repaired = SubtitleFileRepair.repaired(Self.broken)
        #expect(repaired?.hasPrefix("1\n00:03:45,000 --> 00:03:47,500\nFine line.\n\n2\n00:03:49,437 --> 00:03:52,189\n") == true)
        #expect(repaired?.contains("granddaughter") == false)
        #expect(repaired?.contains("4\n00:14:45,000 --> 00:14:46,000\nNext.\n") == true)
    }

    @Test func aNumberAsDialogueStaysText() {
        let text = "1\n00:00:01,000 --> 00:00:02,000\nWhat year?\n1984\n\n2\n00:00:03,000 --> 00:00:04,000\nOkay.\n"
        #expect(SubtitleFileRepair.cues(in: text).first?.lines == ["What year?", "1984"])
    }

    @Test func otherFormatsAreLeftToThePlayer() {
        #expect(SubtitleFileRepair.repaired("WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nHi.\n") == nil)
        #expect(SubtitleFileRepair.repaired("[Script Info]\nTitle: x\n") == nil)
    }
}
