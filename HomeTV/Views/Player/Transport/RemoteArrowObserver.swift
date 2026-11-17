import SwiftUI
import UIKit

/// Puts a `RemoteArrowRecognizer` on the window while this view is on screen, so it sees Left/Right
/// whichever control has focus.
struct RemoteArrowObserver: UIViewRepresentable {
    let onPress: (PlayerScan.Direction) -> Bool
    let onClick: (PlayerScan.Direction) -> Void
    let onHold: (PlayerScan.Direction) -> Void

    func makeUIView(context: Context) -> HostView {
        HostView()
    }

    func updateUIView(_ view: HostView, context: Context) {
        view.recognizer.onPress = onPress
        view.recognizer.onClick = onClick
        view.recognizer.onHold = onHold
    }

    final class HostView: UIView {
        let recognizer = RemoteArrowRecognizer()

        override func willMove(toWindow newWindow: UIWindow?) {
            super.willMove(toWindow: newWindow)
            recognizer.view?.removeGestureRecognizer(recognizer)
            newWindow?.addGestureRecognizer(recognizer)
        }
    }
}
