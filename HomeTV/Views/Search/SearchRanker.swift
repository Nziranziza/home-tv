import Foundation

/// Relevance ordering for search hits. Addon results arrive in whatever order the concurrent fetches
/// finish, so the strongest title match is not naturally at the front — this puts it there.
///
/// Deliberately a plain `enum` of pure static functions over `MetaPreview`: no view, no networking, no
/// actor, so the Top Results order is unit-testable on its own.
enum SearchRanker {
    /// How well a title matches the query, best first. Raw values order the tiers.
    enum MatchTier: Int, Comparable, Sendable {
        /// The title *is* the query ("silo" → Silo).
        case exact
        /// The title starts with the query ("si" → Silo).
        case prefix
        /// Some later word of the title starts with the query ("si" → Bad Sisters).
        case wordPrefix
        /// The query appears somewhere in the title ("si" → The Silence of the Lambs).
        case substring
        /// No title match at all — the addon returned it, so it is kept, just last.
        case unmatched

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Everything the sort compares, derived once per item rather than inside the comparator.
    private struct Ranked {
        let meta: MetaPreview
        let tier: MatchTier
        let rating: Double
        let year: Int
    }

    /// Orders hits by title-match strength, breaking ties on rating then year (both descending) and
    /// finally on name/id so the result is stable for identical inputs.
    static func rank(_ metas: [MetaPreview], query: String) -> [MetaPreview] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return metas }

        return metas
            .map {
                Ranked(meta: $0, tier: tier(title: $0.name, query: trimmed),
                       rating: rating(of: $0), year: year(of: $0))
            }
            .sorted(by: isOrderedBefore)
            .map(\.meta)
    }

    /// Match strength of one title against the query. Case- and diacritic-insensitive throughout, via
    /// `localizedStandardContains`-style comparison.
    static func tier(title: String, query: String) -> MatchTier {
        let title = title.trimmingCharacters(in: .whitespaces)
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return .unmatched }

        if title.compare(query, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            return .exact
        }
        if hasPrefix(title, query) { return .prefix }
        // Split on word boundaries, not just spaces: the matching word of a punctuated title
        // (Spider-Man, Marvel's, Mission: Impossible) starts after a hyphen, apostrophe or colon,
        // and would otherwise be demoted to a substring match. No `dropFirst` — a title-leading
        // match already returned `.prefix` above, so anything left is a genuine later-word hit.
        if title.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .contains(where: { hasPrefix(String($0), query) }) {
            return .wordPrefix
        }
        if title.localizedStandardContains(query) { return .substring }
        return .unmatched
    }

    // MARK: - Comparison

    private static func isOrderedBefore(_ lhs: Ranked, _ rhs: Ranked) -> Bool {
        if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
        if lhs.rating != rhs.rating { return lhs.rating > rhs.rating }
        if lhs.year != rhs.year { return lhs.year > rhs.year }
        if lhs.meta.name != rhs.meta.name { return lhs.meta.name < rhs.meta.name }
        return lhs.meta.id < rhs.meta.id
    }

    private static func hasPrefix(_ title: String, _ query: String) -> Bool {
        title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil
    }

    /// IMDB rating as the popularity stand-in (addon metadata carries no popularity figure). Missing or
    /// unparseable ratings sort last within their tier rather than jumping ahead of a rated title.
    private static func rating(of meta: MetaPreview) -> Double {
        Double(meta.imdbRating ?? "") ?? 0
    }

    /// Leading year of `releaseInfo`, which is a bare year ("2012") for films and a range ("2012-2015"
    /// or "2012-") for series. 0 when absent.
    private static func year(of meta: MetaPreview) -> Int {
        guard let info = meta.releaseInfo else { return 0 }
        return Int(info.prefix(4)) ?? 0
    }
}
