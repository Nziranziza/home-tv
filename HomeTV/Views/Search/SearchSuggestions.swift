import Foundation

/// Builds the suggestion chips shown under the keyboard. There is no suggestion backend — the terms
/// are the titles and cast names the current query already returned, narrowed to the ones that
/// actually match what has been typed, so a chip is always a term with results behind it.
///
/// Pure and view-free, like `SearchRanker`, so the chip list is unit-testable.
enum SearchSuggestions {
    /// How many chips the row holds.
    static let limit = 8

    /// Suggestion terms for `query`, ranked titles first then people, lowercased (as on Apple TV),
    /// de-duplicated, and with the query itself dropped — a chip that re-runs what is already typed is
    /// dead weight.
    static func build(query: String, titles: [String], people: [String]) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return [] }

        var seen: Set<String> = [trimmed.lowercased()]
        var suggestions: [String] = []
        for candidate in titles + people {
            let term = candidate.trimmingCharacters(in: .whitespaces).lowercased()
            guard !term.isEmpty,
                  SearchRanker.tier(title: term, query: trimmed) != .unmatched,
                  seen.insert(term).inserted else { continue }
            suggestions.append(term)
            if suggestions.count == limit { break }
        }
        return suggestions
    }
}
