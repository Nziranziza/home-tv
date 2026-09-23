import Foundation

/// One card in the In Theaters & At Home row: the title to open, plus which release window it is in.
/// The window is all the caption needs — the card's glyph, and the availability its accessibility
/// label spells out, derive from it and nothing else (see `InTheatersCaptionText`), which is what
/// keeps that formatting testable without a network.
struct TheatricalItem: Identifiable, Hashable, Sendable {
    let preview: MetaPreview
    let availability: TheatricalAvailability

    var id: String { preview.id }
}

/// How you can watch a title right now. Declared in the order the row shows them — in cinemas first,
/// then at home newest-first — so the source can sort by it.
enum TheatricalAvailability: Hashable, Sendable, CaseIterable {
    /// Currently in cinemas.
    case inTheaters
    /// Digital release landed within the last couple of weeks.
    case newlyAvailable
    /// Out to buy or rent for a while now.
    case buyOrRent
}
