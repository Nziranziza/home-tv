import SwiftUI
import UIKit

/// Hosts the engine's video view. UIKit because the engines render into a `UIView`.
struct PlayerVideoSurface: UIViewRepresentable {
    let videoView: UIView

    func makeUIView(context: Context) -> UIView { videoView }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
