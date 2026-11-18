import Foundation

/// A part of the title the viewer can skip, checked against the file's length.
struct SkipSegment: Equatable, Sendable {
    enum Kind: CaseIterable, Sendable {
        case intro
        case recap
        case credits

        /// The button's label.
        var title: String {
            switch self {
            case .intro: "Skip Intro"
            case .recap: "Skip Recap"
            case .credits: "Skip Credits"
            }
        }
    }

    let kind: Kind
    let start: TimeInterval
    let end: TimeInterval
    /// For credits, where a scene after them starts.
    let scene: TimeInterval?

    init(kind: Kind, start: TimeInterval, end: TimeInterval, scene: TimeInterval? = nil) {
        self.kind = kind
        self.start = start
        self.end = end
        self.scene = scene
    }

    /// Where Skip goes: the scene after the credits, else the end.
    var target: TimeInterval { scene ?? end }
}
