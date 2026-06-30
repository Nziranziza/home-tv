import Foundation

/// View-facing person payload produced by `TMDBService` from a raw `TMDBPersonDetail`. Drives the
/// cast/crew screen: the header (name + headshot + biography) and the filmography rows grouped by role
/// ("Movies", "Producer", "Guest Appearances", …).
///
/// Like `Enrichment`, this is the sidecar the view reads so `CastView` never touches TMDB's wire format.
struct PersonProfile: Sendable, Hashable {
    let id: Int
    let name: String
    let biography: String?
    let profileURL: URL?
    let sections: [FilmographySection]
}

/// One titled filmography group. `style` selects the row layout: poster cards (films / crew work) or
/// landscape cards with a caption (TV guest appearances).
struct FilmographySection: Sendable, Hashable, Identifiable {
    enum Style: Sendable, Hashable { case poster, landscape }

    var id: String { title }
    let title: String
    let style: Style
    let items: [FilmographyItem]
}

/// One entry in a filmography row. `preview` carries the artwork/title/genre the cards render and a
/// `TMDBRef`-encoded id (resolved to an IMDB id on select, like the Related row). `role` is the
/// person's character/job, shown as the landscape card's caption.
struct FilmographyItem: Sendable, Hashable, Identifiable {
    var id: String { preview.id }
    let preview: MetaPreview
    let role: String?
}
