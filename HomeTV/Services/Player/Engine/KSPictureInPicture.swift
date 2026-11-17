#if canImport(KSPlayer)
import AVKit
import KSPlayer

/// KSPlayer's Picture in Picture controller, set as `KSOptions.pictureInPictureType`. KSPlayer's own
/// suspends the app; this one reports to the engine, so the app stays navigable under the corner.
///
/// KSPlayer calls `didStart(layer:)` once the video is in the corner, `stop(restoreUserInterface: false)`
/// when it closes, and `stop(restoreUserInterface: true)` on expand without completing AVKit's handler.
/// The relay takes over expand to complete it. KSPlayer calls in on the main thread.
final class KSPictureInPicture: AVPictureInPictureController, KSPictureInPictureProtocol {
    private weak var layer: KSComplexPlayerLayer?
    private var relay: PictureInPictureRelay?
    private var possibleObservation: NSKeyValueObservation?

    func start(layer: KSComplexPlayerLayer) {
        self.layer = layer
        MainActor.assumeIsolated { installRelay(on: layer) }
        guard !isPictureInPicturePossible else { return startPictureInPicture() }
        // A sample-buffer source turns possible a moment after it's set up.
        possibleObservation = observe(\.isPictureInPicturePossible, options: [.new]) { controller, change in
            guard change.newValue == true else { return }
            controller.possibleObservation = nil
            controller.startPictureInPicture()
        }
    }

    func didStart(layer: KSComplexPlayerLayer) {
        self.layer = layer
        MainActor.assumeIsolated {
            // Again, in case KSPlayer set its layer as delegate after `start`.
            installRelay(on: layer)
            Self.engine(of: layer)?.onPictureInPicture?(.started)
        }
    }

    func stop(restoreUserInterface: Bool) {
        possibleObservation = nil
        if !restoreUserInterface, isPictureInPictureActive { stopPictureInPicture() }
        guard let layer else { return }
        MainActor.assumeIsolated {
            // A restore here means the relay was bypassed, so there's no handler to complete.
            Self.engine(of: layer)?.onPictureInPicture?(restoreUserInterface ? .restore { _ in } : .stopped)
        }
    }

    static func play(layer _: KSComplexPlayerLayer) {}

    @MainActor
    private func installRelay(on layer: KSComplexPlayerLayer) {
        let relay = relay ?? PictureInPictureRelay(forwardingTo: layer)
        relay.onRestore = { [weak layer] completion in
            guard let layer, let engine = Self.engine(of: layer) else { return completion(false) }
            engine.onPictureInPicture?(.restore(completion: completion))
        }
        self.relay = relay
        if delegate !== relay { delegate = relay }
    }

    @MainActor
    private static func engine(of layer: KSComplexPlayerLayer) -> KSPlaybackEngine? {
        layer.delegate as? KSPlaybackEngine
    }
}
#endif
