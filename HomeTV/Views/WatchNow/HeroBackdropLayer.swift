import SwiftUI

/// The Watch Now hero's **pinned** layer: full-bleed backdrop + inline trailer + scrims. It sits
/// behind the scroll view and stays fixed while the content sheet scrolls up over it, fading out as
/// the hero collapses (`opacity` is driven by the caller from the scroll clock) so that once you're
/// into the rows the backdrop is gone and the opaque sheet reads as flat page colour, not artwork.
///
/// All carousel + trailer lifecycle lives here (it's always present whenever there are items), reading
/// the shared `HeroCarouselModel`; the focusable logo/buttons live in the sibling `HeroOverlay`.
struct HeroBackdropLayer: View {
    let model: HeroCarouselModel

    var body: some View {
        ZStack {
            HeroBackdropContent(model: model)
            HeroScrim()
        }
        .clipped()
        .ignoresSafeArea()
        // Item-reset: when the feed changes, jump back to the first title and warm its neighbours.
        // Keyed on items only — NOT isActive — so covering/uncovering the hero never resets the page.
        .task(id: model.items.map(\.id)) {
            model.resetToFirst()
        }
        // Timer-driven auto-advance, gated on isActive so the carousel doesn't keep paging underneath a
        // pushed detail. Keyed on isActive too so toggling pauses/resumes without disturbing the index.
        .task(id: "\(model.items.map(\.id))|\(model.isActive)") {
            guard model.isActive else { return }
            await model.autoAdvance()
        }
        // Load + autoplay the current title's trailer. Re-runs when the featured item changes or the
        // hero is covered/uncovered, so a covered hero tears its player down and a returning one reloads.
        .task(id: "\(model.currentItem?.id ?? "none")|\(model.isActive)") {
            await model.loadTrailer()
        }
        .onChange(of: model.index) { _, _ in model.prefetchNeighbors() }
        .onDisappear { model.trailer.teardown() }
    }

}

// MARK: - Backdrop (current item only; the next is prefetched into the image cache)

/// The backdrop still + inline trailer crossfade, split into its own `View` (not a computed property)
/// so the layer's body stays composed of real view types.
private struct HeroBackdropContent: View {
    let model: HeroCarouselModel

    var body: some View {
        ZStack {
            if let meta = model.currentItem {
                HeroBackdrop(url: meta.background.flatMap(URL.init(string:)))
                    .id(meta.id)
                    .transition(pageTransition)
            }
            // The inline trailer crossfades over the still once it's producing frames.
            TrailerVideoLayer(player: model.trailer.player)
                .scaleEffect(Theme.Hero.trailerFillZoom)   // crop baked-in scope letterbox to fill the hero
                .opacity(model.trailer.isReady ? 1 : 0)
                .animation(.easeInOut(duration: Theme.Hero.crossfadeDuration), value: model.trailer.isReady)
                .allowsHitTesting(false)
        }
    }

    /// Horizontal page-slide that follows the paging direction, shared with `HeroOverlay` so the
    /// backdrop and the text/logo page as one.
    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: model.forward ? .trailing : .leading),
            removal: .move(edge: model.forward ? .leading : .trailing)
        )
    }
}

// MARK: - Backdrop image

private struct HeroBackdrop: View {
    let url: URL?

    @State private var drift = false

    var body: some View {
        RemoteImage(url: url, targetSize: Theme.Hero.backdropTargetSize, contentMode: .fill) {
            Color(white: 0.04)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(drift ? Theme.Hero.kenBurnsScale : Theme.Hero.kenBurnsBaseScale, anchor: .center)
        .offset(
            x: drift ? -Theme.Hero.kenBurnsOffsetX : Theme.Hero.kenBurnsOffsetX,
            y: drift ? -Theme.Hero.kenBurnsOffsetY : Theme.Hero.kenBurnsOffsetY
        )
        .animation(
            .easeInOut(duration: Theme.Hero.kenBurnsDuration).repeatForever(autoreverses: true),
            value: drift
        )
        .clipped()
        .onAppear { drift = true }
    }
}

// MARK: - Scrim

/// Layered gradients: a top scrim so the tab bar reads over bright art, a left scrim behind the text
/// column, and a bottom scrim that darkens for the hero's own text/buttons.
private struct HeroScrim: View {
    var body: some View {
        ZStack {
            // Top scrim so the tab bar reads over bright art.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.40), location: 0.0),
                    .init(color: .black.opacity(0.0), location: 0.18)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            // Left scrim behind the text column.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.70), location: 0.0),
                    .init(color: .black.opacity(0.15), location: 0.45),
                    .init(color: .black.opacity(0.0), location: 0.65)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            // Bottom scrim that darkens for the hero's own text/buttons.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.0), location: 0.4),
                    .init(color: .black.opacity(0.35), location: 0.7),
                    .init(color: .black.opacity(0.65), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}
