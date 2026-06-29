import SwiftUI
import AVFoundation

/// Full-bleed, chrome-less video surface for the hero trailer. Wraps an `AVPlayerLayer` with
/// `.resizeAspectFill` so the trailer crops to fill the hero exactly like the still backdrop it
/// replaces.
///
/// Deliberately UIKit (the one place the app uses it): AVKit's SwiftUI `VideoPlayer` only aspect-FITS
/// and always draws transport controls, so it can't serve as a cropped, control-free hero background.
struct TrailerVideoLayer: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }

    /// A `UIView` whose backing layer IS an `AVPlayerLayer`, so the video tracks the view's bounds
    /// without manual frame bookkeeping.
    final class PlayerLayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
