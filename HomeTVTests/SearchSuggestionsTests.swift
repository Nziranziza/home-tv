import Testing
@testable import HomeTV

/// The suggestion chips shown under the keyboard.
struct SearchSuggestionsTests {

    @Test func shortQueriesGetNoSuggestions() {
        #expect(SearchSuggestions.build(query: "s", titles: ["Silo"], people: []).isEmpty)
    }

    @Test func titlesComeBeforePeopleAndAreLowercased() {
        let suggestions = SearchSuggestions.build(
            query: "si", titles: ["Silo", "Bad Sisters"], people: ["Sian Brooke"]
        )
        #expect(suggestions == ["silo", "bad sisters", "sian brooke"])
    }

    @Test func termsThatDoNotMatchTheQueryAreDropped() {
        let suggestions = SearchSuggestions.build(query: "si", titles: ["Ted Lasso", "Silo"], people: [])
        #expect(suggestions == ["silo"])
    }

    @Test func theQueryItselfIsNeverSuggested() {
        let suggestions = SearchSuggestions.build(
            query: "Silo", titles: ["Silo", "Silo Behind the Scenes"], people: []
        )
        #expect(suggestions == ["silo behind the scenes"])
    }

    @Test func duplicatesAreCollapsed() {
        let suggestions = SearchSuggestions.build(
            query: "si", titles: ["Silo", "SILO"], people: ["Silo"]
        )
        #expect(suggestions == ["silo"])
    }

    @Test func theRowIsCapped() {
        let titles = (1...20).map { "Sisters \($0)" }
        #expect(SearchSuggestions.build(query: "si", titles: titles, people: []).count == SearchSuggestions.limit)
    }
}
