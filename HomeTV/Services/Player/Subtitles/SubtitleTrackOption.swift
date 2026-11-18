/// A subtitle track as the Language menu lists it.
struct SubtitleTrackOption: Identifiable, Equatable {
    let track: PlaybackTrack
    let name: String
    /// An add-on file's release, shown in grey under its name.
    var detail: String?

    var id: Int32 { track.id }
}
