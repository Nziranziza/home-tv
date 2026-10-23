/// The Subtitles menu's levels. Language and Style replace the top level in place.
enum SubtitlesMenuPage: Hashable {
    case root
    case language
    case style

    var title: String {
        switch self {
        case .root: "Subtitles"
        case .language: "Language"
        case .style: "Style"
        }
    }
}
