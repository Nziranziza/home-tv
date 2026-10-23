/// An audio, subtitle or video track, as the engine reports it.
struct PlaybackTrack: Identifiable, Hashable, Sendable {
    enum Kind: Sendable {
        case audio
        case subtitle
        case video
    }

    let id: Int32
    let kind: Kind
    let name: String
    let languageCode: String?
    let isSelected: Bool
}
