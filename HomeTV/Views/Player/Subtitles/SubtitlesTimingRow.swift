import SwiftUI

/// Timing: Left and Right move the subtitles a tenth of a second earlier or later, applied as they
/// change. Select puts them back in sync with the stream.
struct SubtitlesTimingRow: View {
    let subtitles: PlayerSubtitles

    var body: some View {
        PlayerMenuRow(title: "Timing", value: SubtitleTiming.text(subtitles.delay), action: subtitles.resetDelay)
            // Only Left and Right; nothing in the menu lies beside the row, so they reach this.
            .onMoveCommand { direction in
                switch direction {
                case .left: subtitles.shiftDelay(by: -1)
                case .right: subtitles.shiftDelay(by: 1)
                default: break
                }
            }
            .accessibilityValue(SubtitleTiming.text(subtitles.delay))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: subtitles.shiftDelay(by: 1)
                case .decrement: subtitles.shiftDelay(by: -1)
                @unknown default: break
                }
            }
    }
}
