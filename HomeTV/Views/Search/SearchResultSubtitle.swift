import Foundation

/// The one-line descriptor under a Top Results title — "TV Show · Sci-Fi", "Movie · Drama · 2012".
/// Pulled out of the card so the formatting is unit-testable.
enum SearchResultSubtitle {
    /// Type, then the leading genre, then (films only) the release year. Missing pieces are dropped
    /// rather than left as empty separators.
    static func text(for meta: MetaPreview) -> String {
        var parts = [StremioType.displayLabel(for: meta.type)]
        if let genre = meta.genres?.first, !genre.isEmpty { parts.append(genre) }
        if meta.type == "movie", let year = meta.releaseInfo?.prefix(4), year.count == 4 {
            parts.append(String(year))
        }
        return parts.joined(separator: " · ")
    }
}
