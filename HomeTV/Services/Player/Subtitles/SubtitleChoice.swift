/// A viewer's subtitle choice for one show, carried to its next episodes.
struct SubtitleChoice: Codable, Equatable, Sendable {
    var isOn: Bool
    /// The chosen track's language, as the track reported it.
    var languageCode: String?
    var isSDH = false
    /// The chosen track's title, which tells apart tracks with the same language or none.
    var name: String?
}
