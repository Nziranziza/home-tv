import SwiftUI

extension View {
    /// Fades detail content in as one block once the page is ready. The focus engine skips invisible
    /// views, so hidden controls can't take focus; `.disabled` isn't used because tvOS fades its dimmed
    /// look out on its own, lighting the buttons up after the rest.
    ///
    /// Only the opacity animates. Enrichment lands in the same update as the reveal, and a subtree-wide
    /// animation would slide each changed chip, line and row into place on its own.
    func detailReveal(_ isReady: Bool) -> some View {
        animation(DetailRevealAnimation.fade) { $0.opacity(isReady ? 1 : 0) }
    }
}

enum DetailRevealAnimation {
    /// Measured from the reference clip: text, rows and scrims share one ~0.55s ease-in-out, no motion.
    static let fade: Animation = .easeInOut(duration: 0.55)
}
