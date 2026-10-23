import SwiftUI

/// The transport bar's track: a playhead tick over the full width, elapsed time under the tick and
/// remaining time under the right end.
struct PlayerScrubber: View {
    let model: PlayerModel

    private static let trackHeight: CGFloat = 14

    var body: some View {
        let duration = model.duration
        let time = model.displayTime
        let progress = duration > 0 ? time / duration : 0
        VStack(spacing: 8.5) {
            Capsule()
                .fill(Color(white: 0.07))
                .overlay(alignment: .top) {
                    // The glass rim along the top of the track.
                    Capsule()
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                        .mask(alignment: .top) { Rectangle().frame(height: 3) }
                }
                .overlay {
                    PlayheadLayout(progress: progress) {
                        Rectangle()
                            .fill(.white)
                            .frame(width: 1, height: Self.trackHeight)
                    }
                }
                .frame(height: Self.trackHeight)
            PlayheadLayout(progress: progress) {
                PlayerTimeText(text: PlayerTime.elapsed(time))
                PlayerTimeText(text: PlayerTime.remaining(max(0, duration - time)))
            }
            .padding(.horizontal, 4)
        }
    }
}
