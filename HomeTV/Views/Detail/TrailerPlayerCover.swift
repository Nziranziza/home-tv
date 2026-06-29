import SwiftUI
import AVKit

/// A request to play a title's trailer full-screen, in-app (the Trailerio path that replaces the old
/// YouTube hand-off). Carries the ordered candidate sources so the player can fall through on failure.
struct TrailerPlaybackRequest: Identifiable, Hashable {
    let title: String
    let candidates: [TrailerCandidate]
    var id: String { (candidates.first?.id ?? "") + title }
}

/// Full-screen in-app trailer player with the standard tvOS transport controls (AVKit `VideoPlayer`).
/// Reuses `TrailerPlaybackController` for source fall-through, readiness, and the audio session; plays
/// once (no loop) — the user dismisses with Menu/Back.
struct TrailerPlayerCover: View {
    let request: TrailerPlaybackRequest

    @State private var controller = TrailerPlaybackController()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: controller.player)
                .ignoresSafeArea()
        }
        .onAppear {
            controller.loops = false
            controller.load(request.candidates)
            controller.play()
        }
        .onDisappear { controller.teardown() }
    }
}
