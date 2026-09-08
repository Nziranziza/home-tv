import SwiftUI

/// The hero action row's trailing share control. Shared by the title detail hero and the episode hero.
/// PLACEHOLDER: there is no share sheet wired up yet, so Select is currently a no-op.
struct HeroShareButton: View {
    var body: some View {
        HeroCircleButton(icon: "square.and.arrow.up", accessibilityLabel: "Share") { }
    }
}
