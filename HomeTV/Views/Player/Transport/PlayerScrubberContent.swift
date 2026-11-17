import SwiftUI

/// The track with its played fill and playhead line, the scrub preview above it, and the elapsed time under
/// the playhead with the remaining time at the right end.
struct PlayerScrubberContent: View {
    let model: PlayerModel
    let time: TimeInterval
    let fillTime: TimeInterval

    private static let trackHeight: CGFloat = 14
    /// Between the track's top and the preview, measured against the system player.
    private static let previewGap: CGFloat = 24

    var body: some View {
        let duration = model.duration
        let progress = Self.fraction(time, of: duration)
        let isScrubbing = model.scrub != nil
        let lineHeight = Self.trackHeight + (isScrubbing ? Self.previewGap : 0)
        VStack(spacing: 8.5) {
            Capsule()
                .fill(Color(white: 0.07))
                .overlay(alignment: .leading) {
                    // Dimmer while scanning, as in the system player.
                    Rectangle()
                        .fill(Color(white: model.isScanning ? 0.35 : 0.55))
                        .scaleEffect(x: Self.fraction(fillTime, of: duration), anchor: .leading)
                }
                .clipShape(.capsule)
                .overlay(alignment: .top) {
                    // The glass rim along the top of the track.
                    Capsule()
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                        .mask(alignment: .top) { Rectangle().frame(height: 3) }
                }
                .overlay(alignment: .bottom) {
                    PlayheadLayout(progress: progress) {
                        Rectangle()
                            .fill(.white)
                            .frame(width: 1, height: lineHeight)
                    }
                    .frame(height: lineHeight)
                }
                .overlay(alignment: .bottom) {
                    if isScrubbing {
                        PlayerScrubPreviewLayout(progress: progress, aspectRatio: model.videoAspectRatio) {
                            PlayerScrubPreview(image: model.thumbnails.image)
                        }
                        .offset(y: -(Self.trackHeight + Self.previewGap))
                    }
                }
                .frame(height: Self.trackHeight)
            let indicator = model.timeIndicator
            // A glyph after the time needs room before the remaining time.
            PlayheadLayout(progress: progress, trailingReserve: indicator.map { $0.isLeading ? 0 : 90 } ?? 0) {
                PlayerElapsedTime(time: time, indicator: indicator)
                PlayerTimeText(text: PlayerTime.remaining(max(0, duration - time)))
                    .fixedSize()
                    .frame(minWidth: 0, alignment: .trailing)
                    .clipped()
            }
            .padding(.horizontal, 4)
        }
        // A skip glides the playhead, fill and time together, as on the system player.
        .animation(.easeOut(duration: 0.17), value: model.skipCount)
    }

    private static func fraction(_ time: TimeInterval, of duration: TimeInterval) -> Double {
        duration > 0 ? min(max(time / duration, 0), 1) : 0
    }
}
