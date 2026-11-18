import Foundation

/// Search text plus facet filters. Every part must match.
struct PlayerTestQuery: Equatable, Sendable {
    var text = ""
    var facets: [PlayerTestFacet: String] = [:]

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty && facets.isEmpty }

    func apply(to entries: [PlayerTestEntry]) -> [PlayerTestEntry] {
        guard !isEmpty else { return entries }
        let tokens = PlayerTestSearch.tokens(text)
        return entries.filter { entry in
            facets.allSatisfy { $0.key.value(of: entry) == $0.value }
                && PlayerTestSearch.matches(tokens, words: entry.words)
        }
    }
}
