/// A language the add-ons have files in: one Language menu row, opening the page of its files.
struct SubtitleFileLanguage: Identifiable, Equatable {
    let languageCode: String?
    let name: String
    /// Best match to the stream first.
    let files: [SubtitleTrackOption]

    var id: String { languageCode ?? "" }
}
