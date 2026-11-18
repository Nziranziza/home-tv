import SwiftUI

/// A coloured capsule naming what a file should do.
struct PlayerTestExpectationBadge: View {
    let expect: PlayerTestExpectation

    var body: some View {
        Label(expect.title, systemImage: expect.symbol)
            .font(.caption)
            .foregroundStyle(expect.tint)
            .padding(.horizontal, Theme.Spacing.stack)
            .padding(.vertical, Theme.Spacing.stack / 3)
            .background(expect.tint.opacity(0.12), in: .capsule)
    }
}

extension PlayerTestExpectation {
    var tint: Color {
        switch self {
        case .play: .green
        case .any: .orange
        case .fail: .red
        }
    }
}
