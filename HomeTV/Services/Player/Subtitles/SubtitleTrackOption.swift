/// A subtitle track as the Language menu lists it.
struct SubtitleTrackOption: Identifiable, Equatable {
    let track: PlaybackTrack
    let name: String

    var id: Int32 { track.id }
}
