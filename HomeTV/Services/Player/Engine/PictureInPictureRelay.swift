import AVKit

/// AVKit's Picture in Picture delegate as closures. `target` gets every call first; KSPlayer's layer
/// moves the video and subtitles in and out of the corner there.
final class PictureInPictureRelay: NSObject, AVPictureInPictureControllerDelegate {
    var onStart: (() -> Void)?
    var onStop: (() -> Void)?
    var onRestore: ((@escaping (Bool) -> Void) -> Void)?
    private weak var target: (any AVPictureInPictureControllerDelegate)?

    init(forwardingTo target: (any AVPictureInPictureControllerDelegate)? = nil) {
        self.target = target
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        target?.pictureInPictureControllerDidStartPictureInPicture?(controller)
        onStart?()
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        target?.pictureInPictureControllerDidStopPictureInPicture?(controller)
        onStop?()
    }

    func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: any Error
    ) {
        target?.pictureInPictureController?(controller, failedToStartPictureInPictureWithError: error)
        onStop?()
    }

    /// Not forwarded: KSPlayer's layer drops the completion handler.
    func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        guard let onRestore else { return completionHandler(false) }
        onRestore(completionHandler)
    }
}
