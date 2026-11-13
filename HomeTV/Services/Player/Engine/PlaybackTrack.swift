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
    /// Subtitles only for the foreign-language parts of the audio.
    var isForced = false
    /// Subtitles for the deaf and hard of hearing.
    var isSDH = false
    /// An add-on's subtitle file rather than one of the stream's own tracks.
    var isExternal = false
    /// The container's default track.
    var isDefault = false
    /// Audio flagged as the title's original language.
    var isOriginal = false
    /// Audio flagged as a dub, so not the original.
    var isDub = false
    /// Audio narrating the picture for blind and low-vision viewers.
    var isAudioDescription = false
    /// Audio codec, by FFmpeg's name: `truehd`, `ac3`, `dts`.
    var codec: String?
    /// Codec profile, such as `DTS-HD MA`.
    var codecProfile: String?
    var channelCount: Int?
}
