import Testing
@testable import HomeTV

/// The "TV Show · Sci-Fi" / "Movie · Drama · 2012" line under a Top Results title.
struct SearchResultSubtitleTests {

    @Test func aSeriesReadsAsTypeAndGenre() {
        let meta = Fixture.meta("Silo", type: "series", genres: ["Sci-Fi", "Drama"], releaseInfo: "2023-")
        #expect(SearchResultSubtitle.text(for: meta) == "TV Show · Sci-Fi")
    }

    @Test func aFilmAlsoCarriesItsYear() {
        let meta = Fixture.meta("Silver Linings Playbook", type: "movie", genres: ["Drama"], releaseInfo: "2012")
        #expect(SearchResultSubtitle.text(for: meta) == "Movie · Drama · 2012")
    }

    @Test func missingPiecesAreDroppedRatherThanLeftBlank() {
        #expect(SearchResultSubtitle.text(for: Fixture.meta("Untitled", type: "movie")) == "Movie")
    }
}
