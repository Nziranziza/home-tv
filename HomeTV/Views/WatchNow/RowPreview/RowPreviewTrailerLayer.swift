import SwiftUI

/// The inline trailer inside the centred card. Its own view, so only it observes `isReady`.
struct RowPreviewTrailerLayer: View {
    let controller: TrailerPlaybackController

    var body: some View {
        TrailerVideoLayer(player: controller.player)
            // Crops the baked-in letterbox, as the detail hero does.
            .scaleEffect(Theme.Hero.trailerFillZoom)
            .opacity(controller.isReady ? 1 : 0)
            .animation(.easeInOut(duration: 0.6), value: controller.isReady)
            .allowsHitTesting(false)
    }
}
