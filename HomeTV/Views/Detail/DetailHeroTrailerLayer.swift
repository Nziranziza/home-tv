import SwiftUI

/// The inline hero trailer, layered directly over the sharp still backdrop. It crossfades in only once
/// the video is actually producing frames (`controller.isReady`) and tracks the collapse clock —
/// `opacity = 1 - p` — so it fades back to the still as the hero collapses into the browse layout,
/// matching the way the sharp image layer beneath it fades.
///
/// Playback follows the scroll collapse: the trailer plays only while the hero is expanded (`active`),
/// pausing as you scroll into the browse layout and resuming when you scroll back — the player is kept
/// alive across the collapse so resuming is instant. Being *covered* (a pushed detail, picker, or the
/// full-screen player) is handled in `MetaDetailView`, which tears the player down to reclaim its
/// buffer and reloads on return.
struct DetailHeroTrailerLayer: View {
    let controller: TrailerPlaybackController
    let scroll: DetailScrollState

    /// Expanded hero (State A) → the trailer should be running.
    private var active: Bool { scroll.p <= 0.12 }

    var body: some View {
        TrailerVideoLayer(player: controller.player)
            .scaleEffect(Theme.Hero.trailerFillZoom)   // crop baked-in scope letterbox to fill the hero
            .ignoresSafeArea()
            .opacity(controller.isReady ? Double(max(0, 1 - scroll.p)) : 0)
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.6), value: controller.isReady)
            .onChange(of: active) { _, isActive in
                if isActive { controller.play() } else { controller.pause() }
            }
            // When a player first becomes available (the title's candidates loaded), kick off the
            // delayed autoplay — but only if the hero is currently the active surface.
            .onChange(of: controller.player == nil) { _, noPlayer in
                if !noPlayer, active { controller.autoplay() }
            }
    }
}
