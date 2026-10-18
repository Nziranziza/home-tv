import Foundation

/// A subtitle track an add-on attached to a stream.
struct StreamSubtitle: Codable, Hashable, Sendable {
    let id: String?
    let url: String?
    /// ISO 639 code, e.g. `eng` or `en`.
    let lang: String?
}
