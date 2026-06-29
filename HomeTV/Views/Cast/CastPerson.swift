import Foundation

/// The navigation value pushed when a Cast & Crew headshot is selected. Carries just enough to open
/// the cast screen and paint its header immediately (name + headshot) while the full TMDB person
/// profile loads. Hashable/Identifiable so it can drive `navigationDestination(item:)`.
struct CastPerson: Identifiable, Hashable {
    /// TMDB person id.
    let id: Int
    let name: String
    /// The headshot already shown in the Cast & Crew row, reused so the header has art on first frame.
    let profileURL: URL?
}
