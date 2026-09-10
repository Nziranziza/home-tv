import Foundation

/// One browsable genre. `id` is the addon's own option string, sent back as the `genre` extra.
struct Genre: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let displayName: String

    init(id: String, displayName: String? = nil) {
        self.id = id
        self.displayName = displayName ?? GenreDirectory.displayName(for: id)
    }
}
