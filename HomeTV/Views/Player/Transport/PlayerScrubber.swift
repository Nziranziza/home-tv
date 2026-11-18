import SwiftUI

/// The transport bar's track. Redraws every frame only while a scan moves the position.
struct PlayerScrubber: View {
    let model: PlayerModel

    var body: some View {
        TimelineView(.animation(paused: !model.isScanning)) { _ in
            // Values, not just the model, so each frame re-renders the content.
            PlayerScrubberContent(model: model, time: model.displayTime, fillTime: model.fillTime)
        }
    }
}
