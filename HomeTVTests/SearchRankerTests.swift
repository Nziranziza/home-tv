import Testing
@testable import HomeTV

/// Top Results ordering. `SearchRanker` is pure, so these run without a view, a network or an addon.
struct SearchRankerTests {

    // MARK: - Tiers

    @Test func exactTitleMatchOutranksEverything() {
        let ranked = SearchRanker.rank(
            [Fixture.meta("Silver Linings Playbook"), Fixture.meta("Silo"), Fixture.meta("Bad Sisters")],
            query: "silo"
        )
        #expect(ranked.first?.name == "Silo")
    }

    @Test func exactMatchIgnoresCaseAndDiacritics() {
        #expect(SearchRanker.tier(title: "Amélie", query: "amelie") == .exact)
        #expect(SearchRanker.tier(title: "SILO", query: "silo") == .exact)
    }

    @Test func prefixBeatsWordPrefixBeatsSubstring() {
        let ranked = SearchRanker.rank(
            [
                Fixture.meta("Missing"),                 // substring — no word starts with "si"
                Fixture.meta("Bad Sisters"),             // word prefix
                Fixture.meta("Silver Linings Playbook")  // prefix
            ],
            query: "si"
        )
        #expect(ranked.map(\.name) == ["Silver Linings Playbook", "Bad Sisters", "Missing"])
    }

    @Test func tiersAreClassifiedIndependently() {
        #expect(SearchRanker.tier(title: "Silo", query: "silo") == .exact)
        #expect(SearchRanker.tier(title: "Silver Linings Playbook", query: "si") == .prefix)
        #expect(SearchRanker.tier(title: "Bad Sisters", query: "si") == .wordPrefix)
        // A leading article doesn't demote a title: "Silence" is still a word prefix.
        #expect(SearchRanker.tier(title: "The Silence of the Lambs", query: "si") == .wordPrefix)
        #expect(SearchRanker.tier(title: "Missing", query: "si") == .substring)
        #expect(SearchRanker.tier(title: "Ted Lasso", query: "si") == .unmatched)
    }

    @Test func aWordAfterPunctuationStillCountsAsAWordPrefix() {
        #expect(SearchRanker.tier(title: "Spider-Man", query: "man") == .wordPrefix)
        #expect(SearchRanker.tier(title: "Mission: Impossible", query: "imp") == .wordPrefix)
        #expect(SearchRanker.tier(title: "Marvel's Runaways", query: "run") == .wordPrefix)
    }

    @Test func aPunctuatedTitleOutranksATrueSubstringMatch() {
        let ranked = SearchRanker.rank(
            [Fixture.meta("Batman Begins"), Fixture.meta("Spider-Man")],
            query: "man"
        )
        // Spider-Man's second word starts with the query; Batman only contains it mid-word.
        #expect(ranked.map(\.name) == ["Spider-Man", "Batman Begins"])
    }

    @Test func unmatchedHitsAreKeptButSortLast() {
        let ranked = SearchRanker.rank([Fixture.meta("Ted Lasso"), Fixture.meta("Silo")], query: "silo")
        #expect(ranked.map(\.name) == ["Silo", "Ted Lasso"])
    }

    // MARK: - Tie-breaks

    @Test func ratingBreaksTiesWithinATier() {
        let ranked = SearchRanker.rank(
            [Fixture.meta("Sisters", rating: "6.1"), Fixture.meta("Sister Act", rating: "8.4")],
            query: "sis"
        )
        #expect(ranked.map(\.name) == ["Sister Act", "Sisters"])
    }

    @Test func yearBreaksTiesWhenRatingsAreEqual() {
        let ranked = SearchRanker.rank(
            [
                Fixture.meta("Sister Act", rating: "7.0", releaseInfo: "1992"),
                Fixture.meta("Sisters", rating: "7.0", releaseInfo: "2015")
            ],
            query: "sis"
        )
        #expect(ranked.map(\.name) == ["Sisters", "Sister Act"])
    }

    @Test func aSeriesRangeYieldsItsOpeningYear() {
        let ranked = SearchRanker.rank(
            [
                Fixture.meta("Sisterhood", rating: "7.0", releaseInfo: "2001-2004"),
                Fixture.meta("Sisters Grimm", rating: "7.0", releaseInfo: "2019-")
            ],
            query: "sis"
        )
        #expect(ranked.map(\.name) == ["Sisters Grimm", "Sisterhood"])
    }

    @Test func unratedTitlesSortBehindRatedOnes() {
        let ranked = SearchRanker.rank(
            [Fixture.meta("Sisters"), Fixture.meta("Sister Act", rating: "5.0")],
            query: "sis"
        )
        #expect(ranked.map(\.name) == ["Sister Act", "Sisters"])
    }

    @Test func fullyTiedHitsFallBackToNameThenIDSoTheOrderIsStable() {
        let items = [
            Fixture.meta("Sisters", id: "tt2"),
            Fixture.meta("Sisters", id: "tt1"),
            Fixture.meta("Sister Act", id: "tt3")
        ]
        let ranked = SearchRanker.rank(items, query: "sis")
        #expect(ranked.map(\.id) == ["tt3", "tt1", "tt2"])
        #expect(SearchRanker.rank(items.reversed(), query: "sis").map(\.id) == ranked.map(\.id))
    }

    // MARK: - Degenerate input

    @Test func anEmptyQueryLeavesTheOrderAlone() {
        let items = [Fixture.meta("Ted Lasso"), Fixture.meta("Silo")]
        #expect(SearchRanker.rank(items, query: "   ").map(\.name) == ["Ted Lasso", "Silo"])
    }

    @Test func rankingKeepsEveryHit() {
        let items = (1...20).map { Fixture.meta("Title \($0)") }
        #expect(SearchRanker.rank(items, query: "title").count == 20)
    }
}
