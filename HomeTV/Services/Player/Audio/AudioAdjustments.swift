/// Enhance Dialogue and Reduce Loud Sounds, applied to every title.
struct AudioAdjustments: Codable, Equatable, Sendable {
    enum DialogueEnhancement: String, Codable, CaseIterable, Sendable {
        case off
        case enhance
        case enhanceMore

        var title: String {
            switch self {
            case .off: "Off"
            case .enhance: "Enhance"
            case .enhanceMore: "Enhance More"
            }
        }
    }

    var dialogue: DialogueEnhancement = .off
    var reducesLoudSounds = false

    var isActive: Bool { dialogue != .off || reducesLoudSounds }
}
