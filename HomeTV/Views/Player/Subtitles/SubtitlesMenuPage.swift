/// The Subtitles menu's levels. Language and Style replace the top level in place, and an add-on
/// language's files replace Language.
enum SubtitlesMenuPage: Hashable {
    case root
    case language
    case style
    /// The add-on files in one language, titled with its name.
    case files(languageCode: String?, name: String)

    var title: String {
        switch self {
        case .root: "Subtitles"
        case .language: "Language"
        case .style: "Style"
        case .files(_, let name): name
        }
    }
}
