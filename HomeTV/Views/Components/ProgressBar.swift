import SwiftUI

/// A thin white playback-progress capsule over a translucent track, sized by the caller's frame.
/// `progress` is clamped to 0…1. Shared by the Continue Watching cards and the detail hero's resume bar.
struct ProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.3))
                Capsule()
                    .fill(.white)
                    .frame(width: geo.size.width * max(0, min(1, progress)))
            }
        }
    }
}
