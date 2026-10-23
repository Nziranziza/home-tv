/// A viewer's subtitle choice for one show, carried to its next episodes.
struct SubtitleChoice: Codable, Equatable, Sendable {
    var isOn: Bool
    /// The chosen track's language, as the track reported it.
    var languageCode: String?
    var isSDH = false
}
