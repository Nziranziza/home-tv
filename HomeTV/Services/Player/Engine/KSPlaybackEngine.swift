#if canImport(KSPlayer)
import AVFoundation
import KSPlayer
import Libavformat
import Observation
import UIKit

/// KSPlayer engine: AVPlayer for MP4/MOV/HLS (native Dolby Vision and Atmos), FFmpeg for the rest, and
/// FFmpeg again for any native start that fails. KSPlayer's types stay in the engine files.
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
    @ObservationIgnored var audioPicker: (@Sendable ([PlaybackTrack]) -> PlaybackTrack?)?

    @ObservationIgnored private var layer: KSPlayerLayer?
    @ObservationIgnored private var options: KSPlaybackOptions?
    /// The layer's own accurate-seek setting, which an audio switch overrides until the next seek.
    @ObservationIgnored private var seeksAccurately = false
    @ObservationIgnored private var source: (url: URL, headers: [String: String], startTime: TimeInterval)?
    @ObservationIgnored private var route: PlaybackRoute = .native
    /// A start time the native route still has to seek to; KSAVPlayer ignores `startPlayTime`.
    @ObservationIgnored private var pendingStart: TimeInterval?
    /// The native start's seek is in flight; it plays when it lands.
    @ObservationIgnored private var isSeekingToStart = false
    @ObservationIgnored private(set) var isSeeking = false
    /// Tells a finished seek from one superseded by a newer seek.
    @ObservationIgnored private var seekGeneration = 0
    @ObservationIgnored private let displaySwitch = DisplayModeSwitch()
    /// Playback waits while the TV blacks out to change mode, instead of playing unseen.
    @ObservationIgnored private var isHoldingForDisplaySwitch = false

    init() {
        videoView.backgroundColor = .black
        Self.configureSubtitles()
        displaySwitch.onStart = { [weak self] in self?.holdForDisplaySwitch() }
        displaySwitch.onEnd = { [weak self] in self?.releaseDisplaySwitchHold() }
    }

    /// Text subtitles take the system caption style. ASS draws through libass, keeping its own styling.
    private static func configureSubtitles() {
        KSOptions.useMACaptionAppearance = true
        KSOptions.isASSUseImageRender = true
    }

    func load(url: URL, headers: [String: String], startTime: TimeInterval) {
        source = (url, headers, startTime)
        // Before the layer opens, so the switch its first frame triggers is caught.
        displaySwitch.startObserving()
        start(on: PlaybackRoute.forURL(url), at: startTime)
    }

    /// KSPlayerLayer's own native-to-FFmpeg fallback doesn't fire (an MP4 whose video AVPlayer can't
    /// decode just fails), so each start runs on exactly one decoder and `finish` handles the retry.
    private func start(on route: PlaybackRoute, at startTime: TimeInterval) {
        guard let source else { return }
        tearDownLayer()
        self.route = route
        let options = KSPlaybackOptions()
        options.audioPicker = audioPicker
        options.startPlayTime = startTime
        // Held until `readyToPlay` seeks there, so the first frame is already at the start time.
        pendingStart = route == .native && startTime > 0 ? startTime : nil
        options.isAutoPlay = pendingStart == nil
        // On the exact second, not the keyframe before it.
        options.isAccurateSeek = pendingStart != nil
        seeksAccurately = options.isAccurateSeek
        self.options = options
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
        // A FFmpeg retry can start mid-switch.
        if displaySwitch.isInProgress { holdForDisplaySwitch() }
    }

    private func holdForDisplaySwitch() {
        guard let layer, let options, !isHoldingForDisplaySwitch else { return }
        isHoldingForDisplaySwitch = true
        PlaybackDiagnostics.log("hold for display mode switch")
        options.isAutoPlay = false
        if layer.state.isPlaying { layer.pause() }
        state = .loading
    }

    private func releaseDisplaySwitchHold() {
        guard isHoldingForDisplaySwitch, let layer, let options else { return }
        isHoldingForDisplaySwitch = false
        PlaybackDiagnostics.log("display mode switch done")
        // A held native start plays once its seek lands.
        guard pendingStart == nil, !isSeekingToStart else { return }
        if layer.player.isReadyToPlay { layer.play() } else { options.isAutoPlay = true }
    }

    func play() { layer?.play() }

    func pause() { layer?.pause() }

    func seek(to time: TimeInterval) {
        guard let layer else { return }
        seekGeneration += 1
        let generation = seekGeneration
        isSeeking = true
        options?.isAccurateSeek = seeksAccurately
        layer.seek(time: time, autoPlay: state != .paused) { [weak self] _ in
            guard let self, generation == seekGeneration else { return }
            isSeeking = false
        }
    }

    func tracks(of kind: PlaybackTrack.Kind) -> [PlaybackTrack] {
        guard let player = layer?.player else { return [] }
        if kind == .subtitle { return player.subtitlesTracks.map(Self.subtitleTrack) }
        if kind == .audio { return player.tracks(mediaType: .audio).map { Self.audioTrack($0) } }
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
        // FFmpeg reseeks to pick up the new stream; inexact, that jumps back to the previous keyframe.
        if track.kind == .audio, route == .ffmpeg { options?.isAccurateSeek = true }
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
        let native = nativeOption(info)
        return PlaybackTrack(
            id: trackID(info),
            kind: .subtitle,
            name: info.name,
            languageCode: info.languageCode,
            isSelected: info.isSelected,
            isForced: ffmpeg?.isForced == true
                || native?.hasMediaCharacteristic(.containsOnlyForcedSubtitles) == true
                || nameHas("forced", name),
            isSDH: disposition & AV_DISPOSITION_HEARING_IMPAIRED != 0
                || native?.hasMediaCharacteristic(.describesMusicAndSoundForAccessibility) == true
                || nameHas("sdh", name)
        )
    }

    /// Off the main actor too: `KSPlaybackOptions.wantedAudio` maps tracks on the demuxer's thread.
    nonisolated static func audioTrack(_ track: any MediaPlayerTrack) -> PlaybackTrack {
        let ffmpeg = track as? FFmpegAssetTrack
        let disposition = ffmpeg?.stream?.pointee.disposition ?? 0
        let native = nativeOption(track)
        let name = track.name.lowercased()
        let channels = ffmpeg.map { Int($0.codecpar.pointee.ch_layout.nb_channels) }
            ?? track.audioStreamBasicDescription.map { Int($0.mChannelsPerFrame) }
        return PlaybackTrack(
            id: track.trackID,
            kind: .audio,
            name: track.name,
            languageCode: track.languageCode,
            isSelected: track.isEnabled,
            isDefault: ffmpeg?.isDefault == true,
            isOriginal: disposition & AV_DISPOSITION_ORIGINAL != 0
                || native?.hasMediaCharacteristic(.isOriginalContent) == true,
            isDub: disposition & AV_DISPOSITION_DUB != 0,
            isAudioDescription: disposition & AV_DISPOSITION_VISUAL_IMPAIRED != 0
                || native?.hasMediaCharacteristic(.describesVideoForAccessibility) == true
                || nameHas("ad", name) || nameHas("description", name) || nameHas("descriptive", name),
            codec: ffmpeg?.codecName ?? nativeCodec(track.mediaSubType.rawValue),
            codecProfile: ffmpeg?.profileName,
            channelCount: channels.flatMap { $0 > 0 ? $0 : nil }
        )
    }

    /// FFmpeg's name for a native track's audio format.
    private nonisolated static func nativeCodec(_ fourCC: FourCharCode) -> String? {
        switch fourCC {
        case kAudioFormatAC3: "ac3"
        case kAudioFormatEnhancedAC3: "eac3"
        case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2: "aac"
        case kAudioFormatAppleLossless: "alac"
        case kAudioFormatFLAC: "flac"
        case kAudioFormatOpus: "opus"
        case kAudioFormatMPEGLayer3: "mp3"
        case kAudioFormatLinearPCM: "pcm"
        default: nil
        }
    }

    /// An AVPlayer track's selection option, found by its name and language since KSPlayer doesn't expose it.
    private nonisolated static func nativeOption(_ info: Any) -> AVMediaSelectionOption? {
        guard let track = info as? AVMediaSelectionTrack, let options = track.group?.options else { return nil }
        let matches = options.filter {
            $0.displayName == track.name
                && ($0.extendedLanguageTag ?? $0.locale?.identifier) == track.languageCode
        }
        return matches.count == 1 ? matches.first : nil
    }

    /// Whether a lowercased title tags the track with `word`, not counting `Non-Forced` or `not SDH`.
    private nonisolated static func nameHas(_ word: String, _ name: String) -> Bool {
        let words = name.split { !$0.isLetter && !$0.isNumber }
        return words.indices.contains { index in
            words[index] == word && (index == 0 || !["non", "not", "no"].contains(words[index - 1]))
        }
    }

    /// Embedded tracks carry their stream's id; anything else is told apart by its subtitle id.
    private static func trackID(_ info: any SubtitleInfo) -> Int32 {
        (info as? any MediaPlayerTrack)?.trackID ?? Int32(truncatingIfNeeded: info.subtitleID.hashValue)
    }

    func stop() {
        onFinish = nil
        onTracksReady = nil
        tearDownLayer()
        displaySwitch.reset()
    }

    private func tearDownLayer() {
        // A cleared delegate first, or the stop reports a state change into a torn-down engine.
        layer?.delegate = nil
        layer?.stop()
        layer = nil
        options = nil
        isSeeking = false
        isHoldingForDisplaySwitch = false
        isSeekingToStart = false
        videoView.subviews.forEach { $0.removeFromSuperview() }
    }
}

extension KSPlaybackEngine: KSPlayerLayerDelegate {
    func player(layer: KSPlayerLayer, state: KSPlayerState) {
        if state == .readyToPlay, let start = pendingStart {
            pendingStart = nil
            PlaybackDiagnostics.log("native start seek to \(start)")
            isSeekingToStart = true
            // Played here rather than by the seek, since a mode switch can start while it's in flight.
            layer.seek(time: start, autoPlay: false) { [weak self, weak layer] _ in
                guard let self, let layer, layer === self.layer else { return }
                isSeekingToStart = false
                videoView.subviews.forEach { $0.isHidden = false }
                if !isHoldingForDisplaySwitch { layer.play() }
            }
        }
        if state == .readyToPlay {
            // A turn later, so the layer has finished its own ready handling and listed the tracks.
            Task { @MainActor [weak self] in self?.onTracksReady?() }
        }
        // The hold's own pause isn't the viewer's, so the player keeps showing it as loading.
        if isHoldingForDisplaySwitch, state != .error, state != .playedToTheEnd {
            self.state = .loading
            return
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
