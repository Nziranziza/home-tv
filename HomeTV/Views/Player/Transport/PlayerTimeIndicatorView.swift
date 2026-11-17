import SwiftUI

/// A skip, scan, loading or pause glyph. A scan above level 1 shows its level on the side away from the time.
struct PlayerTimeIndicatorView: View {
    let indicator: PlayerTimeIndicator

    var body: some View {
        // Each side renders as the system player's 13pt once the bearings are added.
        HStack(spacing: 0) {
            if case .scan(let scan) = indicator, scan.direction == .backward, scan.level > 1 {
                PlayerTimeText(text: scan.level.formatted())
                    .padding(.trailing, 9)
            }
            if case .loading(let direction) = indicator {
                // Laid out in the skip glyph's box and centred on its circle, below the arrowhead, so the
                // swap doesn't move anything, as on the system player. tvOS ignores `controlSize`, so the
                // 40pt spinner is scaled to the system player's 24pt.
                Image(systemName: direction == .backward ? "gobackward.10" : "goforward.10")
                    .imageScale(.large)
                    .hidden()
                    .overlay(alignment: .bottom) {
                        Image(systemName: "circle")
                            .imageScale(.large)
                            .hidden()
                            .overlay {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.6)
                            }
                    }
            } else {
                Image(systemName: symbol)
                    .imageScale(.large)
                    .contentTransition(.identity)
            }
            if case .scan(let scan) = indicator, scan.direction == .forward, scan.level > 1 {
                PlayerTimeText(text: scan.level.formatted())
                    .padding(.leading, 7)
            }
        }
        .font(.caption2)
        .bold()
        .foregroundStyle(.white)
        .accessibilityHidden(true)
    }

    private var symbol: String {
        switch indicator {
        case .skip(.backward): "gobackward.10"
        case .skip(.forward): "goforward.10"
        case .scan(let scan): scan.direction == .forward ? "forward.circle" : "backward.circle"
        case .loading, .paused: "pause.circle"
        }
    }
}
