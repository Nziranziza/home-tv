/// The Audio menu's levels. Enhance Dialogue's choices replace the top level in place.
enum AudioMenuPage: Hashable {
    case root
    case enhanceDialogue

    var title: String {
        switch self {
        case .root: "Audio Adjustments"
        case .enhanceDialogue: "Enhance Dialogue"
        }
    }
}
