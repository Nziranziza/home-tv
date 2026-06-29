import Foundation
import Observation

/// Owns the cast screen's content: the loaded TMDB `PersonProfile` (bio + grouped filmography). A thin
/// async loader mirroring `MetaDetailModel`, so the view stays declarative and the network/grouping
/// lives off the render path.
///
/// `@MainActor @Observable` (the project applies strict concurrency with no default actor isolation):
/// the view re-renders only when `profile`/`status` change.
@MainActor
@Observable
final class CastViewModel {
    enum LoadStatus { case loading, loaded, failed }

    let person: CastPerson
    private(set) var profile: PersonProfile?
    private(set) var status: LoadStatus = .loading

    init(person: CastPerson) {
        self.person = person
    }

    /// Display name — the loaded profile's name once available, else the name carried in from the row.
    var name: String {
        let loaded = profile?.name ?? ""
        return loaded.isEmpty ? person.name : loaded
    }

    /// Headshot — the higher-res profile image once loaded, else the row's thumbnail.
    var profileURL: URL? { profile?.profileURL ?? person.profileURL }

    var biography: String? { profile?.biography }
    var sections: [FilmographySection] { profile?.sections ?? [] }

    func load() async {
        status = .loading
        if let loaded = await TMDBService.shared.personProfile(id: person.id) {
            profile = loaded
            status = .loaded
        } else {
            status = .failed
        }
    }
}
