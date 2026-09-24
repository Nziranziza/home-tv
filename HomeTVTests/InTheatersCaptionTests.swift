import Testing
@testable import HomeTV

/// The copy for a showcase card in the In Theaters & At Home row: the "Movie · Sci-Fi · Adventure"
/// type line the card shows, its glyph, and the availability phrase its accessibility label uses.
struct InTheatersCaptionTests {

    // MARK: - Type line

    @Test func aFilmReadsAsTypeThenGenres() {
        let meta = Fixture.meta("Project Hail Mary", type: "movie", genres: ["Sci-Fi", "Adventure"])
        #expect(InTheatersCaptionText.genreLine(for: meta) == "Movie · Sci-Fi · Adventure")
    }

    @Test func atMostTwoGenresFitTheCard() {
        let meta = Fixture.meta("Galaxy", type: "movie", genres: ["Animation", "Kids & Family", "Comedy"])
        #expect(InTheatersCaptionText.genreLine(for: meta) == "Movie · Animation · Kids & Family")
    }

    @Test func aSingleGenreLeavesNoTrailingSeparator() {
        let meta = Fixture.meta("The Mummy", type: "movie", genres: ["Horror"])
        #expect(InTheatersCaptionText.genreLine(for: meta) == "Movie · Horror")
    }

    @Test func missingGenresLeaveTheTypeAlone() {
        #expect(InTheatersCaptionText.genreLine(for: Fixture.meta("Untitled", type: "movie")) == "Movie")
    }

    @Test func blankGenresAreDroppedRatherThanShownAsEmptySeparators() {
        let meta = Fixture.meta("Untitled", type: "movie", genres: ["", "  ", "Drama"])
        #expect(InTheatersCaptionText.genreLine(for: meta) == "Movie · Drama")
    }

    @Test func theLineFollowsTheTitlesOwnType() {
        let meta = Fixture.meta("Silo", type: "series", genres: ["Sci-Fi", "Adventure"])
        #expect(InTheatersCaptionText.genreLine(for: meta) == "TV Show · Sci-Fi · Adventure")
    }

    // MARK: - Availability

    @Test func eachWindowHasItsOwnTagline() {
        #expect(InTheatersCaptionText.tagline(for: .newlyAvailable) == "Now available to buy or rent.")
        #expect(InTheatersCaptionText.tagline(for: .buyOrRent) == "Buy or rent it now.")
        #expect(InTheatersCaptionText.tagline(for: .inTheaters) == "In theaters now.")
    }

    @Test func everyWindowSaysSomething() {
        for availability in TheatricalAvailability.allCases {
            #expect(!InTheatersCaptionText.tagline(for: availability).isEmpty)
        }
    }

    @Test func theGlyphIsABagOnceYouCanBuyItAndATicketUntilThen() {
        #expect(InTheatersCaptionText.glyph(for: .newlyAvailable) == "bag.fill")
        #expect(InTheatersCaptionText.glyph(for: .buyOrRent) == "bag.fill")
        #expect(InTheatersCaptionText.glyph(for: .inTheaters) == "ticket.fill")
    }
}
