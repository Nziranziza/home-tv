import SwiftUI

/// The Next Episode button's icon: a play glyph in a ring that runs down to the hand-over. Its own view so
/// the per-second update redraws only the ring.
struct UpNextCountdownRing: View {
    let model: PlayerModel

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: model.upNextCountdownFraction)
                .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: model.upNextSecondsLeft)
            Image(systemName: "play.fill")
                .font(.callout)
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }
}
