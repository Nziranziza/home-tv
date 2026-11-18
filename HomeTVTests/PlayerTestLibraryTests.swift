import Foundation
import Testing
@testable import HomeTV

/// The test-branch sample library: decoding, search, filters, quick tests and the What to check guide.
struct PlayerTestLibraryTests {

    static let json = """
    {
      "itemCount": 4, "generated": "2026-11-18",
      "sections": [{
        "id": "modern", "title": "Modern Video", "summary": "Jellyfin", "expect": "play",
        "groups": [{
          "id": "modern.dolby-vision", "title": "Dolby Vision",
          "items": [
            { "title": "4K DV P8.1", "url": "https://example.com/a/dv%20clip.mp4", "container": "mp4",
              "size": 1200000000, "video": "hevc", "audio": null, "resolution": "2160p", "hdr": "dolbyVision",
              "bitrate": null, "headers": null, "note": null, "expect": null },
            { "title": "240p", "url": "https://example.com/b.mkv", "container": "mkv", "video": "h264",
              "audio": "eac3", "resolution": "240p" }
          ]
        }]
      }, {
        "id": "subtitles", "title": "Subtitles", "summary": "Formats", "expect": "any",
        "groups": [{
          "id": "subtitles.pgs", "title": "PGS",
          "items": [
            { "title": "movie.m2ts", "url": "https://example.com/c.m2ts", "container": "m2ts",
              "headers": { "Referer": "https://example.com/" }, "note": "Needs the Referer header.",
              "expect": "fail" },
            { "title": "sup.mkv", "url": "https://example.com/d.mkv", "container": "mkv" }
          ]
        }]
      }]
    }
    """

    static func index() throws -> PlayerTestIndex {
        PlayerTestIndex(try PlayerTestCatalog.decode(Data(json.utf8)))
    }

    static func titles(_ entries: [PlayerTestEntry]) -> [String] { entries.map(\.item.title) }

    @Test func indexesEveryItemWithItsSectionExpectation() throws {
        let index = try Self.index()
        #expect(index.entries.map(\.id) == [0, 1, 2, 3])
        #expect(index.entries.map(\.expect) == [.play, .play, .fail, .any])
        #expect(index.entries[2].breadcrumb == "Subtitles › PGS")
        #expect(index.sections.map(\.itemCount) == [2, 2])
        #expect(index.verified != nil)
    }

    @Test func detailLineUsesPresentFields() throws {
        let entries = try Self.index().entries
        let size = Int64(1_200_000_000).formatted(.byteCount(style: .file))
        #expect(entries[0].item.detailLine == "MP4 · HEVC · 2160p · Dolby Vision · \(size)")
        #expect(entries[1].item.detailLine == "MKV · H.264 · E-AC-3 · 240p")
        #expect(entries[0].item.filename == "dv clip.mp4")
    }

    @Test(arguments: [
        ("dolby vision", ["4K DV P8.1", "240p"]),   // group title covers the whole group
        ("dv", ["4K DV P8.1"]),
        ("h.265", ["4K DV P8.1"]),
        ("HEVC 4k", ["4K DV P8.1"]),
        ("dolby digital plus", ["240p"]),
        ("pgs", ["movie.m2ts", "sup.mkv"]),
        ("vision 8k", []),
    ])
    func searchMatchesWordPrefixesAndAliases(query: String, expected: [String]) throws {
        let entries = try Self.index().entries
        #expect(Self.titles(PlayerTestQuery(text: query).apply(to: entries)) == expected)
    }

    @Test func facetsNarrowAndCountOptions() throws {
        let entries = try Self.index().entries
        var query = PlayerTestQuery()
        query.facets[.container] = "mkv"
        #expect(Self.titles(query.apply(to: entries)) == ["240p", "sup.mkv"])
        query.facets[.result] = "any"
        #expect(Self.titles(query.apply(to: entries)) == ["sup.mkv"])
        let containers = PlayerTestFacet.container.options(in: entries)
        #expect(containers.map(\.title) == ["M2TS", "MKV", "MP4"])
        #expect(containers.map(\.count) == [1, 2, 1])
        #expect(PlayerTestFacet.result.options(in: entries).map(\.value) == ["play", "any", "fail"])
    }

    @Test func quickTestsMatchByTextOrSection() throws {
        let index = try Self.index()
        #expect(index.presetCounts["dolby-vision"] == 2)
        #expect(index.presetCounts["subtitles"] == 2)
        #expect(index.presetCounts["eac3"] == 1)
        let scope = try #require(index.scope(for: .preset("4k")))
        #expect(Self.titles(scope.entries) == ["4K DV P8.1"])
    }

    @Test func scopesOfferOnlyFacetsWithChoices() throws {
        let scope = try #require(try Self.index().scope(for: .section("modern")))
        let facets = scope.facets.map(\.facet)
        #expect(facets.contains(.resolution))
        #expect(!facets.contains(.group))     // one group
        #expect(!facets.contains(.section))
    }

    @Test func guideExplainsWhatToCheck() throws {
        let entries = try Self.index().entries
        let dolbyVision = PlayerTestGuide.checks(for: entries[0])
        #expect(dolbyVision.first == PlayerTestExpectation.play.explanation)
        #expect(dolbyVision.contains { $0.contains("Dolby Vision") })
        #expect(dolbyVision.contains { $0.contains("4K") })
        let referer = PlayerTestGuide.checks(for: entries[2])
        #expect(referer.contains { $0.contains("Referer") })
        #expect(referer.contains { $0.contains("subtitle") })
    }

    @Test func infuseIsBlockedForHeadersAndLocalFiles() throws {
        let entries = try Self.index().entries
        #expect(entries[0].item.infuseBlockReason == nil)
        #expect(entries[2].item.infuseBlockReason == "Needs the Referer header.")
        let local = PlayerTestItem(title: "x.mkv", url: URL(filePath: "/tmp/x.mkv"), container: "mkv")
        #expect(local.infuseBlockReason != nil)
    }

    @Test @MainActor func remembersTheLastPlayAcrossLaunches() async throws {
        let suite = "PlayerTestLibraryTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let item = try Self.index().entries[1].item
        await PlayerTestLibrary(defaults: defaults).play(item, expect: .play, in: .builtIn)
        let replay = try #require(PlayerTestLibrary(defaults: defaults).lastPlayed)
        #expect(replay.item == item)
        #expect(replay.player == .builtIn)
        PlayerPresenter.shared.request = nil
    }
}
