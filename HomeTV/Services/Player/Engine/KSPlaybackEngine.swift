#if canImport(KSPlayer)
import AVFoundation
import KSPlayer
import Libavformat
import Observation
import UIKit

/// KSPlayer engine: AVPlayer for MP4/MOV/HLS (native Dolby Vision and Atmos), FFmpeg for the rest, and
/// FFmpeg again for any native start that fails. KSPlayer's types stay in this file.
@MainActor
@Observable
final class KSPlaybackEngine: PlaybackEngine {
    @ObservationIgnored let videoView = UIView()
    private(set) var state: PlaybackState = .idle
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    var subtitleDelay: TimeInterval = 0 {
        didSet { layer?.subtitleModel.subtitleDelay = subtitleDelay }
    }
    @ObservationIgnored var onFinish: ((Error?) -> Void)?
    @ObservationIgnored var onTracksReady: (() -> Void)?

    @ObservationIgnored private var layer: KSPlayerLayer?
    @ObservationIgnored private var source: (url: URL, headers: [String: String], startTime: TimeInterval)?
    @ObservationIgnored private var route: PlaybackRoute = .native
    /// A start time the native route still has to seek to; KSAVPlayer ignores `startPlayTime`.
    @ObservationIgnored private var pendingStart: TimeInterval?
    @ObservationIgnored private(set) var isSeeking = false
    /// Tells a finished seek from one superseded by a newer seek.
    @ObservationIgnored private var seekGeneration = 0

    init() {
        videoView.backgroundColor = .black
        Self.configureSubtitles()
    }

    /// Text subtitles take the system caption style. ASS draws through libass, keeping its own styling.
    private static func configureSubtitles() {
        KSOptions.useMACaptionAppearance = true
        KSOptions.isASSUseImageRender = true
    }

    func load(url: URL, headers: [String: String], startTime: TimeInterval) {
        source = (url, headers, startTime)
        start(on: PlaybackRoute.forURL(url), at: startTime)
    }

    /// KSPlayerLayer's own native-to-FFmpeg fallback doesn't fire (an MP4 whose video AVPlayer can't
    /// decode just fails), so each start runs on exactly one decoder and `finish` handles the retry.
    private func start(on route: PlaybackRoute, at startTime: TimeInterval) {
        guard let source else { return }
        tearDownLayer()
        self.route = route
        let options = KSOptions()
        options.startPlayTime = startTime
        // Held until `readyToPlay` seeks there, so the first frame is already at the start time.
        pendingStart = route == .native && startTime > 0 ? startTime : nil
        options.isAutoPlay = pendingStart == nil
        // On the exact second, not the keyframe before it.
        options.isAccurateSeek = pendingStart != nil
        // `NowPlayingController` owns Now Playing and the remote commands for both engines.
        options.registerRemoteControll = false
        // `PlayerSubtitles` picks the track once `onTracksReady` fires.
        options.autoSelectEmbedSubtitle = false
        if !source.headers.isEmpty { options.appendHeader(source.headers) }
        options.playerTypes = route == .ffmpeg ? [KSMEPlayer.self] : [KSAVPlayer.self]
        state = .loading
        PlaybackDiagnostics.log("load \(route) \(source.url.lastPathComponent) start=\(startTime)")
        let layer = KSPlayerLayer(url: source.url, options: options, delegate: self)
        self.layer = layer
        // Without autoplay the layer doesn't load on its own.
        if !options.isAutoPlay { layer.prepareToPlay() }
        let surface = layer.makeUIView()
        surface.frame = videoView.bounds
        surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // A held start shows frame 0 until the seek lands.
        surface.isHidden = pendingStart != nil
        videoView.addSubview(surface)
    }

    func play() { layer?.play() }

    func pause() { layer?.pause() }

    func seek(to time: TimeInterval) {
        guard let layer else { return }
        seekGeneration += 1
        let generation = seekGeneration
        isSeeking = true
        layer.seek(time: time, autoPlay: state != .paused) { [weak self] _ in
            guard let self, generation == seekGeneration else { return }
            isSeeking = false
        }
    }

    func tracks(of kind: PlaybackTrack.Kind) -> [PlaybackTrack] {
        guard let player = layer?.player else { return [] }
        if kind == .subtitle { return player.subtitlesTracks.map(Self.subtitleTrack) }
        return player.tracks(mediaType: kind.mediaType).map { track in
            PlaybackTrack(
                id: track.trackID,
                kind: kind,
                name: track.name,
                languageCode: track.languageCode,
                isSelected: track.isEnabled
            )
        }
    }

    func select(_ track: PlaybackTrack) {
        guard let player = layer?.player,
              let match = player.tracks(mediaType: track.kind.mediaType).first(where: { $0.trackID == track.id })
        else { return }
        player.select(track: match)
    }

    func selectSubtitle(_ track: PlaybackTrack?) {
        guard let layer else { return }
        let info = track.flatMap { track in layer.player.subtitlesTracks.first { Self.trackID($0) == track.id } }
        layer.select(subtitleInfo: info)
    }

    private static func subtitleTrack(_ info: any SubtitleInfo) -> PlaybackTrack {
        let ffmpeg = info as? FFmpegAssetTrack
        let disposition = ffmpeg?.stream?.pointee.disposition ?? 0
        let name = info.name.lowercased()
        return PlaybackTrack(
            id: trackID(info),
            kind: .subtitle,
            name: info.name,
            languageCode: info.languageCode,
            isSelected: info.isSelected,
            isForced: ffmpeg?.isForced == true || name.contains("forced"),
            isSDH: disposition & AV_DISPOSITION_HEARING_IMPAIRED != 0 || name.contains("sdh")
        )
    }

    /// Embedded tracks carry their stream's id; anything else is told apart by its subtitle id.
    private static func trackID(_ info: any SubtitleInfo) -> Int32 {
        (info as? any MediaPlayerTrack)?.trackID ?? Int32(truncatingIfNeeded: info.subtitleID.hashValue)
    }

    func stop() {
        onFinish = nil
        onTracksReady = nil
        tearDownLayer()
    }

    private func tearDownLayer() {
        // A cleared delegate first, or the stop reports a state change into a torn-down engine.
        layer?.delegate = nil
        layer?.stop()
        layer = nil
        isSeeking = false
        videoView.subviews.forEach { $0.removeFromSuperview() }
    }
}

extension KSPlaybackEngine: KSPlayerLayerDelegate {
    func player(layer: KSPlayerLayer, state: KSPlayerState) {
        if state == .readyToPlay, let start = pendingStart {
            pendingStart = nil
            PlaybackDiagnostics.log("native start seek to \(start)")
            layer.seek(time: start, autoPlay: true) { [weak self] _ in
                self?.videoView.subviews.forEach { $0.isHidden = false }
            }
        }
        if state == .readyToPlay {
            // A turn later, so the layer has finished its own ready handling and listed the tracks.
            Task { @MainActor [weak self] in self?.onTracksReady?() }
        }
        self.state = switch state {
        case .initialized, .preparing, .readyToPlay: .loading
        case .buffering: .buffering
        case .bufferFinished: .playing
        case .paused: .paused
        case .playedToTheEnd: .ended
        case .error: .failed
        @unknown default: self.state
        }
    }

    func player(layer: KSPlayerLayer, currentTime: TimeInterval, totalTime: TimeInterval) {
        self.currentTime = currentTime
        duration = totalTime
    }

    func player(layer: KSPlayerLayer, finish error: Error?) {
        PlaybackDiagnostics.log("finish on \(route): \(error.map { String(describing: $0) } ?? "end")")
        if error != nil, route == .native, let source {
            start(on: .ffmpeg, at: currentTime > 0 ? currentTime : source.startTime)
            return
        }
        let callback = onFinish
        onFinish = nil
        callback?(error)
    }

    func player(layer: KSPlayerLayer, bufferedCount: Int, consumeTime: TimeInterval) {}
}

private extension PlaybackTrack.Kind {
    var mediaType: AVFoundation.AVMediaType {
        switch self {
        case .audio: .audio
        case .subtitle: .subtitle
        case .video: .video
        }
    }
}
#endif
