/// An audio track as the Audio menu lists it.
struct AudioTrackOption: Identifiable, Equatable {
    let track: PlaybackTrack
    /// `Original: English`, `Spanish AD`.
    let title: String
    /// Codec and channels, shown only where titles repeat.
    let detail: String?

    var id: Int32 { track.id }
}
