import Foundation
import Testing
@testable import HomeTV

/// Mapping TMDB discover results into a channel's cards and hero.
struct ChannelTitlesTests {

    private func item(
        _ id: Int,
        title: String? = nil,
        name: String? = nil,
        poster: String? = "/p.jpg",
        genres: [Int]? = nil,
        released: String? = nil,
        aired: String? = nil
    ) -> TMDBDiscoverItem {
        TMDBDiscoverItem(
            id: id, title: title, name: name, overview: nil, posterPath: poster, backdropPath: "/b.jpg",
            genreIds: genres, releaseDate: released, firstAirDate: aired
        )
    }

    @Test func aSeriesReadsItsNameAirDateAndTVGenres() throws {
        let preview = try #require(ChannelTitles.preview(from: item(1, name: "Lanterns", genres: [10765], aired: "2026-08-17"), media: .tv))
        #expect(preview.id == "tmdb:tv:1")
        #expect(preview.type == "series")
        #expect(preview.name == "Lanterns")
        #expect(preview.releaseInfo == "2026")
        #expect(preview.genres == ["Sci-Fi & Fantasy"])
    }

    @Test func aMovieReadsItsTitleAndReleaseDate() throws {
        let preview = try #require(ChannelTitles.preview(from: item(2, title: "Sicario", genres: [28], released: "2015-09-18"), media: .movie))
        #expect(preview.id == "tmdb:movie:2")
        #expect(preview.type == "movie")
        #expect(preview.releaseInfo == "2015")
        #expect(preview.genres == ["Action"])
    }

    @Test func titlesWithoutAPosterOrNameAreDropped() {
        #expect(ChannelTitles.preview(from: item(3, name: "No Art", poster: nil), media: .tv) == nil)
        #expect(ChannelTitles.preview(from: item(4, name: "  "), media: .tv) == nil)
        #expect(ChannelTitles.preview(from: item(5, name: "Series only"), media: .movie) == nil)
    }

    @Test func interleaveAlternatesPagesAndDropsRepeats() {
        let shows = ["a", "b", "c"].map { Fixture.meta($0) }
        let films = ["x", "a"].map { Fixture.meta($0) }
        #expect(ChannelTitles.interleave([shows, films]).map(\.id) == ["a", "x", "b", "c"])
    }

    @Test func topTenIsCappedAtTen() {
        let titles = (1...25).map { Fixture.meta("Title \($0)") }
        let topTen = ChannelTitles.topTen(titles)
        #expect(topTen.count == 10)
        #expect(topTen.first?.name == "Title 1")
    }

    @Test func anEnglishLogoBeatsATextlessOne() {
        let images = TMDBImageList(
            logos: [
                TMDBImage(filePath: "/none.png", code: nil, voteAverage: 9),
                TMDBImage(filePath: "/en-low.png", code: "en", voteAverage: 2),
                TMDBImage(filePath: "/en-high.png", code: "en", voteAverage: 5)
            ],
            backdrops: nil
        )
        #expect(ChannelTitles.preferredLogoPath(images) == "/en-high.png")
    }

    @Test func aTextlessLogoIsTheFallback() {
        let images = TMDBImageList(logos: [TMDBImage(filePath: "/none.png", code: nil, voteAverage: 1)], backdrops: nil)
        #expect(ChannelTitles.preferredLogoPath(images) == "/none.png")
        #expect(ChannelTitles.preferredLogoPath(nil) == nil)
    }

    @Test func theHeroPreviewIsKeyedByIMDBID() {
        let preview = ChannelTitles.heroPreview(Fixture.meta("Lanterns", id: "tmdb:tv:1"), imdbID: "tt123", logo: URL(string: "https://x/l.png"))
        #expect(preview.id == "tt123")
        #expect(preview.name == "Lanterns")
        #expect(preview.logo == "https://x/l.png")
    }
}
