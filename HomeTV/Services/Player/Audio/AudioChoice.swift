/// A viewer's audio track choice for one show, carried to its next episodes.
struct AudioChoice: Codable, Equatable, Sendable {
    /// The chosen track's language, as the track reported it.
    var languageCode: String?
    var isAudioDescription = false
    /// The track's title, codec and channels, which tell apart tracks in the same language.
    var name: String?
    var codec: String?
    var channelCount: Int?

    init(track: PlaybackTrack) {
        languageCode = track.languageCode
        isAudioDescription = track.isAudioDescription
        name = track.name
        codec = track.codec
        channelCount = track.channelCount
    }
}
