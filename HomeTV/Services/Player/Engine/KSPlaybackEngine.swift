#if canImport(KSPlayer)
import AVFoundation
import KSPlayer
import Libavformat
import Libavutil
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
    var externalSubtitles: [ExternalSubtitle] = [] {
        didSet {
            // Files already listed keep their info, so one fetched or selected isn't replaced.
            if !externalSubtitles.starts(with: oldValue) {
                externalInfos = []
                repairedFiles = []
            }
            // Not auto-downloaded: KSPlayer fetches a file the first time it's selected.
            let added = externalSubtitles.dropFirst(externalInfos.count).map {
                URLSubtitleInfo(subtitleID: $0.url.absoluteString, name: "", url: $0.url, languageCode: $0.languageCode)
            }
            externalInfos += added
            // Before `readyToPlay`, the layer is given them all there.
            if let layer, layer.player.isReadyToPlay { added.forEach(layer.subtitleModel.addSubtitle(info:)) }
        }
    }
    @ObservationIgnored var onFinish: ((Error?) -> Void)?
    @ObservationIgnored var onTracksReady: (() -> Void)?
    /// Copied into each start's options and never changed there, since the demuxer's thread reads it. A
    /// later choice reaches an opening stream through `select` once its tracks are listed.
    @ObservationIgnored var audioPicker: (@Sendable ([PlaybackTrack]) -> PlaybackTrack?)?
    @ObservationIgnored var audioAdjustments = AudioAdjustments() {
        didSet { applyAudioAdjustments() }
    }
    private(set) var canAdjustAudio = false

    @ObservationIgnored private var layer: KSPlayerLayer?
    /// Kept across decoder restarts, so a fetched file isn't fetched again.
    @ObservationIgnored private var externalInfos: [URLSubtitleInfo] = []
    /// Add-on files whose info now reads a repaired local copy.
    @ObservationIgnored private var repairedFiles: Set<Int> = []
    @ObservationIgnored private var subtitleRepair: Task<Void, Never>?
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
    /// Prepared ahead of Select: buffering, but not playing or switching the TV's mode until `load`.
    @ObservationIgnored private var isAwaitingLoad = false
    /// Released before `readyToPlay`; the layer ignores `isAutoPlay` set after it opens.
    @ObservationIgnored private var playsWhenReady = false
    /// The FFmpeg route's redirect-free URL, once resolved.
    @ObservationIgnored private var openURL: URL?
    @ObservationIgnored private var resolveTask: Task<Void, Never>?
    /// First-frame timing for the debug log.
    @ObservationIgnored private var hasReportedFirstFrame = false
    /// The native route's audio adjustments, once its tracks are checked.
    @ObservationIgnored private var audioTap: AudioAdjustmentTap?
    @ObservationIgnored private var audioTapTask: Task<Void, Never>?
    /// Watches for the audio hardware changing under the FFmpeg route's `AVAudioEngine`.
    @ObservationIgnored private var audioConfigurationTask: Task<Void, Never>?
    /// The latest engine loaded: the one the session's output channel count is for.
    private static weak var channelOwner: KSPlaybackEngine?

    init() {
        videoView.backgroundColor = .black
        Self.configureSubtitles()
        displaySwitch.onStart = { [weak self] in self?.holdForDisplaySwitch() }
        displaySwitch.onEnd = { [weak self] in self?.releaseDisplaySwitchHold() }
        audioConfigurationTask = Task { [weak self] in
            // Mapped to a `Sendable` id first: `Notification` can't cross into the main actor.
            let engines = NotificationCenter.default.notifications(named: .AVAudioEngineConfigurationChange)
                .compactMap { ($0.object as? AVAudioEngine).map(ObjectIdentifier.init) }
            for await engine in engines {
                self?.audioConfigurationDidChange(engine: engine)
            }
        }
    }

    /// A configuration change stops every `AVAudioEngine`, and KSPlayer doesn't start its own again: the
    /// stream plays on silently with a stalled clock. Up Next's hand-over causes one when the previous
    /// episode's player shuts down; so can the TV changing mode.
    private func audioConfigurationDidChange(engine: ObjectIdentifier) {
        guard let player = layer?.player as? KSMEPlayer,
              let output = player.audioOutput as? AudioEnginePlayer,
              engine == ObjectIdentifier(output.engine) else { return }
        // Another player's open, track switch or late reset may have changed the channels under this one.
        if Self.channelOwner === self { Self.restoreOutputChannels() }
        // KSPlayer's own rule for a running output, so a change landing mid-start is caught too.
        guard !output.engine.isRunning, player.playbackState == .playing, player.loadState == .playable else { return }
        PlaybackDiagnostics.log("audio engine stopped by a configuration change, restarting")
        output.play()
    }

    /// The channels the session should output for this stream. AVPlayer's only count after another player's
    /// reset, since the native route otherwise leaves the session alone.
    private func outputChannelCount(includingNative: Bool) -> Int? {
        guard let player = layer?.player, player.isReadyToPlay,
              let track = player.tracks(mediaType: .audio).first(where: \.isEnabled) else { return nil }
        let count: UInt32? = switch route {
        case .ffmpeg: (track as? FFmpegAssetTrack)?.audioDescriptor?.audioFormat.channelCount
        case .native: includingNative ? track.audioStreamBasicDescription?.mChannelsPerFrame : nil
        }
        return count.map(Int.init)
    }

    /// KSMEPlayer sets the session's output channels when it opens a stream and resets them to 2 when it
    /// stops, whatever else is playing. Up Next has two open at once, so the playing one's count is put back.
    private static func restoreOutputChannels(afterReset: Bool = false) {
        guard let count = channelOwner?.outputChannelCount(includingNative: afterReset) else { return }
        let session = AVAudioSession.sharedInstance()
        // Never below stereo, as KSPlayer sets for mono.
        let wanted = max(2, min(count, session.maximumOutputNumberOfChannels))
        guard session.preferredOutputNumberOfChannels != wanted else { return }
        do {
            try session.setPreferredOutputNumberOfChannels(wanted)
            PlaybackDiagnostics.log("restored output channels to \(wanted)")
        } catch {
            PlaybackDiagnostics.log("restoring output channels to \(wanted) failed: \(error)")
        }
    }

    /// Text subtitles take the system caption style. ASS draws through libass, keeping its own styling.
    private static func configureSubtitles() {
        KSOptions.useMACaptionAppearance = true
        KSOptions.isASSUseImageRender = true
        // The default `AudioEnginePlayer` plus a dynamics processor, for Reduce Loud Sounds.
        KSOptions.audioPlayerType = AudioEngineDynamicsPlayer.self
    }

    func prepare(url: URL, headers: [String: String], startTime: TimeInterval) {
        source = (url, headers, startTime)
        isAwaitingLoad = true
        begin(at: startTime)
    }

    func load(url: URL, headers: [String: String], startTime: TimeInterval) {
        // Before the layer opens or the held mode switch applies, so the switch is caught.
        displaySwitch.startObserving()
        Self.channelOwner = self
        if isAwaitingLoad, let source, source.url == url, source.headers == headers, source.startTime == startTime {
            releasePreparedStart()
            return
        }
        isAwaitingLoad = false
        source = (url, headers, startTime)
        begin(at: startTime)
    }

    /// The FFmpeg route opens the stream's final URL, so its range requests skip the redirects.
    private func begin(at startTime: TimeInterval) {
        guard let source else { return }
        let route = PlaybackRoute.forURL(source.url)
        openURL = nil
        resolveTask?.cancel()
        #if DEBUG
        if ProcessInfo.processInfo.environment["PLAYER_NO_RESOLVE"] == "1" { return start(on: route, at: startTime) }
        #endif
        guard route == .ffmpeg else { return start(on: route, at: startTime) }
        tearDownLayer()
        state = .loading
        resolveTask = Task { [weak self, url = source.url, headers = source.headers] in
            let final = await StreamRedirect.finalURL(of: url, headers: headers)
            guard let self, !Task.isCancelled else { return }
            resolveTask = nil
            openURL = final == url ? nil : final
            start(on: .ffmpeg, at: startTime)
        }
    }

    /// Select on a prepared stream: switches the TV's mode and plays from what's buffered.
    private func releasePreparedStart() {
        isAwaitingLoad = false
        guard let layer, let options else { return }
        PlaybackDiagnostics.log("load prepared, ready=\(layer.player.isReadyToPlay)")
        Self.restoreOutputChannels()
        options.applyDeferredDisplayCriteria()
        if displaySwitch.isInProgress { holdForDisplaySwitch() }
        // A held native start plays once its seek lands; a held switch once it ends.
        guard pendingStart == nil, !isSeekingToStart, !isHoldingForDisplaySwitch else { return }
        if layer.player.isReadyToPlay { layer.play() } else { playsWhenReady = true }
    }

    /// KSPlayerLayer's own native-to-FFmpeg fallback doesn't fire (an MP4 whose video AVPlayer can't
    /// decode just fails), so each start runs on exactly one decoder and `finish` handles the retry.
    private func start(on route: PlaybackRoute, at startTime: TimeInterval) {
        guard let source else { return }
        tearDownLayer()
        self.route = route
        let options = KSPlaybackOptions()
        options.audioPicker = audioPicker
        // Before the first frame decodes; the centre channel is unknown until the tracks are.
        options.audioFilters = AudioFilterGraph.filters(for: audioAdjustments, hasCentreChannel: false)
        options.startPlayTime = startTime
        // Held until `readyToPlay` seeks there, so the first frame is already at the start time.
        pendingStart = route == .native && startTime > 0 ? startTime : nil
        options.isAutoPlay = pendingStart == nil && !isAwaitingLoad
        options.defersDisplayCriteria = isAwaitingLoad
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
        let url = route == .ffmpeg ? openURL ?? source.url : source.url
        PlaybackDiagnostics.log(
            "load \(route) \(source.url.lastPathComponent) start=\(startTime) resolved=\(url != source.url)"
        )
        let layer = KSPlayerLayer(url: url, options: options, delegate: self)
        self.layer = layer
        layer.subtitleModel.subtitleDelay = subtitleDelay
        // Without autoplay the layer doesn't load on its own.
        if !options.isAutoPlay { layer.prepareToPlay() }
        // The output's dynamics processor is on by default; off before the first sample unless wanted.
        applyAudioAdjustments()
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
        playsWhenReady = false
        if layer.state.isPlaying { layer.pause() }
        state = .loading
    }

    private func releaseDisplaySwitchHold() {
        guard isHoldingForDisplaySwitch, let layer else { return }
        isHoldingForDisplaySwitch = false
        PlaybackDiagnostics.log("display mode switch done")
        // A held native start plays once its seek lands.
        guard pendingStart == nil, !isSeekingToStart else { return }
        if layer.player.isReadyToPlay { layer.play() } else { playsWhenReady = true }
    }

    func play() { layer?.play() }

    func pause() {
        // A start still waiting on `readyToPlay` stays paused.
        playsWhenReady = false
        layer?.pause()
    }

    func seek(to time: TimeInterval, isAccurate: Bool) {
        guard let layer else { return }
        seekGeneration += 1
        let generation = seekGeneration
        isSeeking = true
        options?.isAccurateSeek = seeksAccurately || isAccurate
        layer.seek(time: time, autoPlay: state != .paused) { [weak self] _ in
            guard let self, generation == seekGeneration else { return }
            isSeeking = false
        }
    }

    func tracks(of kind: PlaybackTrack.Kind) -> [PlaybackTrack] {
        guard let player = layer?.player else { return [] }
        if kind == .subtitle {
            let external = externalSubtitles.enumerated().map { index, subtitle in
                subtitle.track(at: index, isSelected: externalInfos[index].isSelected)
            }
            return player.subtitlesTracks.map(Self.subtitleTrack) + external
        }
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

    var videoFormat: VideoFormat? {
        guard let tracks = layer?.player.tracks(mediaType: .video),
              let track = tracks.first(where: \.isEnabled) ?? tracks.first else { return nil }
        let range: VideoFormat.DynamicRange = if track.isDovi {
            .dolbyVision
        } else {
            switch track.dynamicRange {
            case .dolbyVision: .dolbyVision
            case .hdr10: .hdr10
            case .hlg: .hlg
            default: .sdr
            }
        }
        let frameRate = track.nominalFrameRate > 0 ? Double(track.nominalFrameRate) : nil
        return VideoFormat(size: track.naturalSize, dynamicRange: range, frameRate: frameRate)
    }

    func select(_ track: PlaybackTrack) {
        guard let player = layer?.player,
              let match = player.tracks(mediaType: track.kind.mediaType).first(where: { $0.trackID == track.id })
        else { return }
        // FFmpeg reseeks to pick up the new stream; inexact, that jumps back to the previous keyframe.
        if track.kind == .audio, route == .ffmpeg { options?.isAccurateSeek = true }
        player.select(track: match)
        if track.kind == .audio {
            applyAudioAdjustments()
            // A prepared stream's switch resets the channels for its own track.
            if route == .ffmpeg, Self.channelOwner !== self { Self.restoreOutputChannels() }
        }
    }

    /// FFmpeg rebuilds its filter graph when the filters change, so they apply mid-play. AVPlayer's go
    /// through the tap installed once its tracks are checked.
    private func applyAudioAdjustments() {
        guard let layer else { return }
        let selected = layer.player.tracks(mediaType: .audio).first(where: \.isEnabled)
        switch route {
        case .ffmpeg:
            options?.audioFilters = AudioFilterGraph.filters(
                for: audioAdjustments, hasCentreChannel: Self.hasCentreChannel(selected)
            )
            if let output = (layer.player as? KSMEPlayer)?.audioOutput as? AudioEngineDynamicsPlayer {
                Self.configureDynamics(output, isOn: audioAdjustments.reducesLoudSounds)
            }
            canAdjustAudio = selected != nil
        case .native:
            audioTap?.update(audioAdjustments)
            let codec = selected.flatMap { Self.audioTrack($0).codec } ?? ""
            canAdjustAudio = audioTap?.isAvailable == true && !AudioAdjustmentTuning.passthroughCodecs.contains(codec)
        }
    }

    /// Reduce Loud Sounds on the FFmpeg route: the output's dynamics processor, bypassed while off. Its EQ
    /// is never used.
    private static func configureDynamics(_ output: AudioEngineDynamicsPlayer, isOn: Bool) {
        output.nbandEQ.bypass = true
        let unit = output.audioUnitForDynamicsProcessor
        var bypass: UInt32 = isOn ? 0 : 1
        AudioUnitSetProperty(
            unit, kAudioUnitProperty_BypassEffect, kAudioUnitScope_Global, 0, &bypass, UInt32(MemoryLayout<UInt32>.size)
        )
        let parameters: [(AudioUnitParameterID, Double)] = [
            (kDynamicsProcessorParam_Threshold, AudioAdjustmentTuning.compressorThreshold),
            (kDynamicsProcessorParam_HeadRoom, AudioAdjustmentTuning.dynamicsHeadroom),
            (kDynamicsProcessorParam_ExpansionRatio, 1),
            (kDynamicsProcessorParam_AttackTime, AudioAdjustmentTuning.compressorAttack),
            (kDynamicsProcessorParam_ReleaseTime, AudioAdjustmentTuning.compressorRelease),
            (kDynamicsProcessorParam_OverallGain, AudioAdjustmentTuning.compressorMakeup),
        ]
        for (parameter, value) in parameters {
            AudioUnitSetParameter(unit, parameter, kAudioUnitScope_Global, 0, AudioUnitParameterValue(value), 0)
        }
    }

    private static func hasCentreChannel(_ track: (any MediaPlayerTrack)?) -> Bool {
        guard let track = track as? FFmpegAssetTrack else { return false }
        var layout = track.codecpar.pointee.ch_layout
        return av_channel_layout_index_from_channel(&layout, AV_CHAN_FRONT_CENTER) >= 0
    }

    /// AVPlayer's audio is tapped once, when it's ready; the tap does nothing while the adjustments are off.
    private func installAudioTap(on layer: KSPlayerLayer) {
        guard route == .native, audioTapTask == nil,
              let item = (layer.player.view as? KSAVPlayerView)?.player.currentItem else { return }
        audioTapTask = Task { [weak self, adjustments = audioAdjustments] in
            let tap = await AudioAdjustmentTap.install(on: item, adjustments: adjustments)
            guard let self, !Task.isCancelled, layer === self.layer else { return }
            audioTap = tap
            applyAudioAdjustments()
        }
    }

    func selectSubtitle(_ track: PlaybackTrack?) {
        guard let layer else { return }
        subtitleRepair?.cancel()
        if let track, let index = ExternalSubtitle.index(of: track), externalInfos.indices.contains(index) {
            selectExternal(at: index)
            return
        }
        let info = track.flatMap { track in layer.player.subtitlesTracks.first { Self.trackID($0) == track.id } }
        layer.select(subtitleInfo: info)
    }

    /// Shows an add-on file from a repaired local copy, made on its first selection, else from its URL.
    private func selectExternal(at index: Int) {
        guard let layer else { return }
        guard !repairedFiles.contains(index), externalSubtitles.indices.contains(index) else {
            layer.select(subtitleInfo: externalInfos[index])
            return
        }
        // Nothing shows while it loads, rather than the previous choice.
        layer.select(subtitleInfo: nil)
        let file = externalSubtitles[index]
        subtitleRepair = Task { [weak self] in
            let local = await SubtitleFileCache.localCopy(of: file.url)
            guard let self, !Task.isCancelled, let layer = self.layer,
                  externalSubtitles.indices.contains(index), externalSubtitles[index] == file else { return }
            if let local {
                let info = URLSubtitleInfo(
                    subtitleID: local.absoluteString, name: "", url: local, languageCode: file.languageCode
                )
                externalInfos[index] = info
                repairedFiles.insert(index)
                layer.subtitleModel.addSubtitle(info: info)
            }
            layer.select(subtitleInfo: externalInfos[index])
        }
    }

    /// FFmpeg lists the file's chapters. When the route lists none, an AVPlayer start's are read from its asset.
    func loadChapters() async -> [PlaybackChapter] {
        guard let player = layer?.player else { return [] }
        let chapters = player.chapters
        if !chapters.isEmpty {
            return chapters.map { PlaybackChapter(start: $0.start, end: $0.end, title: $0.title) }
        }
        guard let asset = (player.view as? KSAVPlayerView)?.player.currentItem?.asset else { return [] }
        return await PlaybackChapter.load(from: asset)
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
        subtitleRepair?.cancel()
        audioConfigurationTask?.cancel()
        audioConfigurationTask = nil
        resolveTask?.cancel()
        resolveTask = nil
        onFinish = nil
        onTracksReady = nil
        tearDownLayer()
        displaySwitch.reset()
    }

    private func tearDownLayer() {
        // A cleared delegate first, or the stop reports a state change into a torn-down engine.
        layer?.delegate = nil
        let resetsChannels = layer?.player is KSMEPlayer
        layer?.stop()
        layer = nil
        if resetsChannels, Self.channelOwner !== self { Self.restoreOutputChannels(afterReset: true) }
        options = nil
        audioTapTask?.cancel()
        audioTapTask = nil
        audioTap = nil
        canAdjustAudio = false
        isSeeking = false
        isHoldingForDisplaySwitch = false
        isSeekingToStart = false
        playsWhenReady = false
        videoView.subviews.forEach { $0.removeFromSuperview() }
    }
}

extension KSPlaybackEngine: KSPlayerLayerDelegate {
    func player(layer: KSPlayerLayer, state: KSPlayerState) {
        PlaybackDiagnostics.log("state \(state)")
        if state == .readyToPlay, let start = pendingStart {
            pendingStart = nil
            PlaybackDiagnostics.log("native start seek to \(start)")
            isSeekingToStart = true
            // Played here rather than by the seek, since a mode switch can start while it's in flight.
            layer.seek(time: start, autoPlay: false) { [weak self, weak layer] _ in
                guard let self, let layer, layer === self.layer else { return }
                isSeekingToStart = false
                videoView.subviews.forEach { $0.isHidden = false }
                if !isHoldingForDisplaySwitch, !isAwaitingLoad { layer.play() }
            }
        }
        if state == .readyToPlay, playsWhenReady, pendingStart == nil, !isSeekingToStart {
            playsWhenReady = false
            layer.play()
        }
        if state == .readyToPlay {
            externalInfos.forEach(layer.subtitleModel.addSubtitle(info:))
            // A prepared stream's open just set the channels for itself, under the episode still playing.
            if route == .ffmpeg { Self.restoreOutputChannels() }
            applyAudioAdjustments()
            installAudioTap(on: layer)
            // A turn later, so the layer has finished its own ready handling and listed the tracks.
            Task { @MainActor [weak self] in self?.onTracksReady?() }
        }
        if state == .bufferFinished, !hasReportedFirstFrame {
            hasReportedFirstFrame = true
            PlaybackDiagnostics.log("stages \(options?.timeLog.description ?? "-")")
            PlaybackDiagnostics.firstFrame(route: "\(route)")
        } else if state == .buffering, hasReportedFirstFrame {
            PlaybackDiagnostics.log("stall at \(Int(currentTime))s")
        }
        // A hold's own pause isn't the viewer's, so the player keeps showing it as loading.
        if isHoldingForDisplaySwitch || isAwaitingLoad, state != .error, state != .playedToTheEnd {
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
        if error != nil, let source, route == .native || openURL != nil {
            // The resolved link may have expired; the original redirects to a fresh one.
            openURL = nil
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
