#if canImport(KSPlayer)
import KSPlayer

/// KSPlayer options that open FFmpeg streams on `audioPicker`'s track, so the first frame already plays it.
final class KSPlaybackOptions: KSOptions, @unchecked Sendable {
    var audioPicker: (@Sendable ([PlaybackTrack]) -> PlaybackTrack?)?

    override func wantedAudio(tracks: [any MediaPlayerTrack]) -> (any MediaPlayerTrack)? {
        guard let audioPicker else { return super.wantedAudio(tracks: tracks) }
        let mapped = tracks.map { KSPlaybackEngine.audioTrack($0) }
        guard let wanted = audioPicker(mapped), let index = mapped.firstIndex(where: { $0.id == wanted.id }) else {
            return super.wantedAudio(tracks: tracks)
        }
        return tracks[index]
    }
}
#endif
