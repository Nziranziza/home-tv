import AVFoundation
import Observation
import UIKit

/// AVPlayer stand-in for builds without KSPlayer (the simulator), so the player UI builds and previews.
/// Plays only what AVPlayer can open, and ignores request headers.
@MainActor
@Observable
final class AVPlaybackEngine: PlaybackEngine {
    @ObservationIgnored let videoView: UIView
    private(set) var state: PlaybackState = .idle
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    var subtitleDelay: TimeInterval = 0
    /// Listed so the menu can be checked, but AVPlayer can't show them.
    var externalSubtitles: [ExternalSubtitle] = []
    @ObservationIgnored private(set) var videoFormat: VideoFormat?
    @ObservationIgnored var onFinish: ((Error?) -> Void)?
    @ObservationIgnored var onTracksReady: (() -> Void)?
    /// Unused: `PlayerAudio` switches to its pick once the tracks are listed.
    @ObservationIgnored var audioPicker: (@Sendable ([PlaybackTrack]) -> PlaybackTrack?)?
    @ObservationIgnored private(set) var isSeeking = false
    @ObservationIgnored private var seekGeneration = 0
    /// Opened by `prepare` and paused until `load`.
    @ObservationIgnored private var preparedURL: URL?

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var endToken: (any NSObjectProtocol)?
    @ObservationIgnored private var legible: AVMediaSelectionGroup?
    @ObservationIgnored private var audible: AVMediaSelectionGroup?

    init() {
        let view = TrailerVideoLayer.PlayerLayerView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        videoView = view
        // `PlayerSubtitles` picks the subtitles, not the system's criteria.
        player.appliesMediaSelectionCriteriaAutomatically = false
    }

    func prepare(url: URL, headers: [String: String], startTime: TimeInterval) {
        open(url, startTime: startTime)
        preparedURL = url
    }

    func load(url: URL, headers: [String: String], startTime: TimeInterval) {
        if preparedURL != url { open(url, startTime: startTime) }
        preparedURL = nil
        player.play()
    }

    private func open(_ url: URL, startTime: TimeInterval) {
        PlaybackDiagnostics.log("load stub \(url.lastPathComponent) start=\(startTime)")
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        state = .loading
        if startTime > 0 {
            player.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
        }
        observe(item)
    }

    func play() { player.play() }

    func pause() { player.pause() }

    func seek(to time: TimeInterval) {
        seekGeneration += 1
        let generation = seekGeneration
        isSeeking = true
        Task { [weak self, player] in
            await player.seek(to: CMTime(seconds: time, preferredTimescale: 600))
            guard let self, generation == seekGeneration else { return }
            isSeeking = false
        }
    }

    /// Track ids are the option's index in its selection group.
    func tracks(of kind: PlaybackTrack.Kind) -> [PlaybackTrack] {
        let external = kind == .subtitle
            ? externalSubtitles.enumerated().map { $1.track(at: $0, isSelected: false) }
            : []
        return groupTracks(of: kind) + external
    }

    private func groupTracks(of kind: PlaybackTrack.Kind) -> [PlaybackTrack] {
        guard let item = player.currentItem, let group = group(for: kind) else { return [] }
        let selected = item.currentMediaSelection.selectedMediaOption(in: group)
        return group.options.enumerated().map { index, option in
            PlaybackTrack(
                id: Int32(index),
                kind: kind,
                name: option.displayName,
                languageCode: option.extendedLanguageTag ?? option.locale?.identifier,
                isSelected: option == selected,
                isForced: option.hasMediaCharacteristic(.containsOnlyForcedSubtitles),
                isSDH: option.hasMediaCharacteristic(.describesMusicAndSoundForAccessibility),
                isOriginal: option.hasMediaCharacteristic(.isOriginalContent),
                isAudioDescription: option.hasMediaCharacteristic(.describesVideoForAccessibility)
            )
        }
    }

    func select(_ track: PlaybackTrack) {
        guard let item = player.currentItem, let group = group(for: track.kind),
              group.options.indices.contains(Int(track.id)) else { return }
        item.select(group.options[Int(track.id)], in: group)
    }

    func selectSubtitle(_ track: PlaybackTrack?) {
        guard let track, !track.isExternal else {
            if let legible { player.currentItem?.select(nil, in: legible) }
            return
        }
        select(track)
    }

    private func group(for kind: PlaybackTrack.Kind) -> AVMediaSelectionGroup? {
        switch kind {
        case .audio: audible
        case .subtitle: legible
        case .video: nil
        }
    }

    func stop() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        statusObservation?.invalidate()
        statusObservation = nil
        if let endToken { NotificationCenter.default.removeObserver(endToken) }
        endToken = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        onFinish = nil
        onTracksReady = nil
    }

    // `.main` queue callbacks, so `assumeIsolated` is safe.
    private func observe(_ item: AVPlayerItem) {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time) }
        }
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            if item.status == .readyToPlay {
                Task { @MainActor [weak self] in
                    await self?.loadSelectionGroups(item)
                    await self?.checkVideoIsPlayable(item)
                }
                return
            }
            guard item.status == .failed else { return }
            Task { @MainActor [weak self] in self?.finish(Self.classify(item.error)) }
        }
        endToken = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(nil) }
        }
    }

    private func loadSelectionGroups(_ item: AVPlayerItem) async {
        let legible = try? await item.asset.loadMediaSelectionGroup(for: .legible)
        let audible = try? await item.asset.loadMediaSelectionGroup(for: .audible)
        let videoFormat = await Self.videoFormat(of: item.asset)
        guard item === player.currentItem else { return }
        self.legible = legible
        self.audible = audible
        self.videoFormat = videoFormat
        onTracksReady?()
    }

    /// nil for HLS, whose asset lists no tracks.
    private static func videoFormat(of asset: AVAsset) async -> VideoFormat? {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let (size, descriptions) = try? await track.load(.naturalSize, .formatDescriptions)
        else { return nil }
        return VideoFormat(size: size, dynamicRange: descriptions.first.map(dynamicRange) ?? .sdr)
    }

    private static func dynamicRange(_ description: CMFormatDescription) -> VideoFormat.DynamicRange {
        let codec = CMFormatDescriptionGetMediaSubType(description)
        if codec == kCMVideoCodecType_DolbyVisionHEVC || codec == FourCharCode(0x6476_6865) { // dvhe
            return .dolbyVision
        }
        let transfer = CMFormatDescriptionGetExtension(
            description, extensionKey: kCMFormatDescriptionExtension_TransferFunction
        ) as? String
        if transfer == kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String { return .hdr10 }
        if transfer == kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String { return .hlg }
        return .sdr
    }

    /// The simulator "plays" video it can't decode (4K Dolby Vision, say) as a black screen with no error.
    private func checkVideoIsPlayable(_ item: AVPlayerItem) async {
        guard let tracks = try? await item.asset.loadTracks(withMediaType: .video), !tracks.isEmpty else { return }
        var playable = false
        for track in tracks where (try? await track.load(.isPlayable)) == true {
            playable = true
        }
        guard !playable, item === player.currentItem else { return }
        player.pause()
        finish(PlaybackError.unsupportedFormat)
    }

    /// AVFoundation's open, parse and decode failures mean the format; anything else (network, server)
    /// passes through.
    private static func classify(_ error: (any Error)?) -> any Error {
        guard let error else { return CocoaError(.fileReadUnknown) }
        let formatCodes: Set<Int> = [
            AVError.fileFormatNotRecognized.rawValue,
            AVError.failedToParse.rawValue,
            AVError.decodeFailed.rawValue,
        ]
        let nsError = error as NSError
        guard nsError.domain == AVFoundationErrorDomain, formatCodes.contains(nsError.code) else { return error }
        return PlaybackError.unsupportedFormat
    }

    private func tick(_ time: CMTime) {
        currentTime = time.seconds
        if let itemDuration = player.currentItem?.duration, itemDuration.isNumeric {
            duration = itemDuration.seconds
        }
        guard state != .ended, state != .failed, preparedURL == nil else { return }
        state = switch player.timeControlStatus {
        case .playing: .playing
        case .paused: currentTime > 0 ? .paused : .loading
        case .waitingToPlayAtSpecifiedRate: .buffering
        @unknown default: state
        }
        if state == .playing { PlaybackDiagnostics.firstFrame(route: "stub") }
    }

    private func finish(_ error: Error?) {
        PlaybackDiagnostics.log("finish: \(error.map { String(describing: $0) } ?? "end")")
        guard state != .ended, state != .failed else { return }
        state = error == nil ? .ended : .failed
        onFinish?(error)
    }
}
