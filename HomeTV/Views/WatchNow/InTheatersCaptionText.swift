import Foundation

/// The copy for a showcase card in the In Theaters & At Home row: the "Movie · Sci-Fi · Adventure"
/// type line and its glyph, plus the availability phrase.
///
/// Pulled out of the view — as `SearchResultSubtitle` is for the Search cards — so the copy is
/// unit-testable without a view or a network.
enum InTheatersCaptionText {
    /// Genres on the type line. Apple's card shows at most two; a third overflows the card's width.
    static let genreLimit = 2

    /// Type, then up to two genres. Missing genres are dropped rather than left as empty separators,
    /// so a title TMDB has no genres for still reads as "Movie" rather than "Movie · · ".
    static func genreLine(for preview: MetaPreview) -> String {
        let genres = (preview.genres ?? [])
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .prefix(genreLimit)
        return ([StremioType.displayLabel(for: preview.type)] + genres).joined(separator: " · ")
    }

    /// What you can do about the title right now, spelled out. The card shows this only through its
    /// glyph — a second line of copy lands on the baked-in wordmark of most posters — so this is what
    /// the card's accessibility label says instead, for anyone who can't read the glyph.
    static func tagline(for availability: TheatricalAvailability) -> String {
        switch availability {
        case .newlyAvailable: "Now available to buy or rent."
        case .buyOrRent: "Buy or rent it now."
        case .inTheaters: "In theaters now."
        }
    }

    /// Symbol for the filled circular glyph beside the type line: a ticket while the film is in
    /// cinemas, a bag once buying or renting it is the way you would watch it.
    static func glyph(for availability: TheatricalAvailability) -> String {
        switch availability {
        case .newlyAvailable, .buyOrRent: "bag.fill"
        case .inTheaters: "ticket.fill"
        }
    }
}
