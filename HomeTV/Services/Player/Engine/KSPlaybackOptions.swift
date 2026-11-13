#if canImport(KSPlayer)
import CoreMedia
import KSPlayer

/// KSPlayer options that open FFmpeg streams on `audioPicker`'s track, so the first frame already plays it.
final class KSPlaybackOptions: KSOptions, @unchecked Sendable {
    var audioPicker: (@Sendable ([PlaybackTrack]) -> PlaybackTrack?)?
    /// Set while a stream is prepared ahead of Select, so its first frame doesn't switch the TV's mode.
    @MainActor var defersDisplayCriteria = false
    @MainActor private var deferredVideo: (refreshRate: Float, isDovi: Bool, format: CMFormatDescription)?

    required init() {
        super.init()
        #if DEBUG
        // Debug A/B against KSPlayer's own defaults.
        if ProcessInfo.processInfo.environment["PLAYER_STOCK_OPTIONS"] == "1" { return }
        #endif
        // A 1s start buffer instead of 3s; the 60s ceiling (default 20s) rides out stalls.
        isSecondOpen = true
        preferredForwardBufferDuration = 1
        maxBufferDuration = 60
    }

    override func wantedAudio(tracks: [any MediaPlayerTrack]) -> (any MediaPlayerTrack)? {
        guard let audioPicker else { return super.wantedAudio(tracks: tracks) }
        let mapped = tracks.map { KSPlaybackEngine.audioTrack($0) }
        guard let wanted = audioPicker(mapped), let index = mapped.firstIndex(where: { $0.id == wanted.id }) else {
            return super.wantedAudio(tracks: tracks)
        }
        return tracks[index]
    }

    override func updateVideo(refreshRate: Float, isDovi: Bool, formatDescription: CMFormatDescription) {
        guard defersDisplayCriteria else {
            return super.updateVideo(refreshRate: refreshRate, isDovi: isDovi, formatDescription: formatDescription)
        }
        PlaybackDiagnostics.log("display criteria deferred")
        deferredVideo = (refreshRate, isDovi, formatDescription)
    }

    /// Select: applies the mode switch the prepared stream held back.
    @MainActor func applyDeferredDisplayCriteria() {
        defersDisplayCriteria = false
        guard let video = deferredVideo else { return }
        deferredVideo = nil
        super.updateVideo(refreshRate: video.refreshRate, isDovi: video.isDovi, formatDescription: video.format)
    }
}
#endif
