import SwiftUI

/// The Watch Now hero's **pinned** layer: full-bleed backdrop + inline trailer + scrims. It sits
/// behind the scroll view and stays fixed while the content sheet scrolls up over it. It keeps full
/// brightness throughout — the opaque sheet simply rises to cover it (Apple TV's Watch Now), so once
/// you're into the rows the backdrop is occluded rather than dimmed.
///
/// All carousel + trailer lifecycle lives here (it's always present whenever there are items), reading
/// the shared `HeroCarouselModel`; the focusable logo/buttons live in the sibling `HeroOverlay`.
struct HeroBackdropLayer: View {
    let model: HeroCarouselModel
    /// The hero's own **full-bleed** width — the width the backdrop actually renders at after it expands
    /// past the safe area, NOT the safe-area-inset width the parent proposes. One page spans this, so the
    /// filmstrip translates by `slot * width - slide * width` and a neighbour sits exactly one viewport off
    /// each edge. Critically the measurement is taken *inside* `.ignoresSafeArea()` (below): read outside
    /// it, `proxy.size.width` is the inset width (~overscan margins narrower), so the +1 neighbour would be
    /// positioned short of the true right edge and a sliver of the next still would peek — the reported bug.
    @State private var width: CGFloat = 0

    var body: some View {
        ZStack {
            HeroBackdropContent(model: model, width: width)
            HeroScrim()
        }
        // Measure BEFORE `.ignoresSafeArea()` so the proxy reports the expanded full-bleed size the ZStack
        // is proposed, not the inset size. Getting this wrong is what left the neighbour peeking at the edge.
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
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

/// The backdrop stills + inline trailer, split into its own `View` (not a computed property) so the
/// layer's body stays composed of real view types.
private struct HeroBackdropContent: View {
    let model: HeroCarouselModel
    let width: CGFloat

    var body: some View {
        ZStack {
            HeroBackdropFilmstrip(model: model, width: width)

            // The inline trailer crossfades over the CURRENT still once it's producing frames. It stays a
            // pinned centre overlay (not part of the sliding strip, since it's torn down and reloaded when
            // the title changes anyway) and is hidden while a page slides, so a playing video never sits
            // static over the moving stills.
            TrailerVideoLayer(player: model.trailer.player)
                .scaleEffect(Theme.Hero.trailerFillZoom)   // crop baked-in scope letterbox to fill the hero
                .opacity(model.trailer.isReady && !model.isPaging ? 1 : 0)
                .animation(.easeInOut(duration: Theme.Hero.crossfadeDuration), value: model.trailer.isReady)
                .allowsHitTesting(false)
        }
    }
}

/// The backdrop stills as a horizontally-translating 3-slot window (previous / current / next), paging in
/// exact lockstep with the overlay text — one rigid surface — rather than as an independent per-item
/// transition. Each slot is a **viewport-width** still positioned by `model.windowOffset(slot:width:)`:
/// the current slot (0) fills the hero at rest, the neighbours (±1) sit one viewport off each edge, and the
/// shared `slide` glides the trio. Because every slot is exactly one viewport wide and `.offset` is
/// render-only, the `ZStack` stays one viewport in size — so it never inflates the sibling trailer layer.
/// Neighbours are prefetched (see `HeroCarouselModel.prefetchNeighbors`), so the incoming still is already
/// decoded and shows no placeholder gap.
private struct HeroBackdropFilmstrip: View {
    let model: HeroCarouselModel
    let width: CGFloat
    /// Ken Burns drift, applied to the whole strip rather than to each still, so it is ONE continuous pan
    /// that never resets when the window's slot contents shift at a page recenter. Per-still drift would
    /// pop the newly-centred image back to the base scale as its view is rebuilt — the "re-adjust after
    /// sliding in" artifact. The pan is slow relative to the page slide, so the two motions don't fight.
    @State private var drift = false

    var body: some View {
        Group {
            if model.canPage, width > 0 {
                ZStack {
                    ForEach([-1, 0, 1], id: \.self) { slot in
                        if let item = model.windowItem(slot) {
                            HeroBackdrop(url: item.background.flatMap(URL.init(string:)))
                                .frame(width: width)
                                .offset(x: model.windowOffset(slot: slot, width: width))
                                .id(item.id)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let meta = model.currentItem {
                // Single featured title: nothing to page, so render the still without a window or offset.
                HeroBackdrop(url: meta.background.flatMap(URL.init(string:)))
                    .id(meta.id)
            }
        }
        .scaleEffect(drift ? Theme.Hero.kenBurnsScale : Theme.Hero.kenBurnsBaseScale, anchor: .center)
        .offset(
            x: drift ? -Theme.Hero.kenBurnsOffsetX : Theme.Hero.kenBurnsOffsetX,
            y: drift ? -Theme.Hero.kenBurnsOffsetY : Theme.Hero.kenBurnsOffsetY
        )
        .animation(kenBurnsAnimation, value: drift)
        // Drive the pan off `isActive` rather than a one-time `onAppear`. When a detail/modal covers Watch
        // Now (isActive == false) the animation below becomes non-repeating, so the `repeatForever` pan
        // actually STOPS instead of compositing the full-screen backdrop forever underneath the covering
        // screen. The settle-to-rest happens while the hero is hidden, so there's no visible change; the
        // pan resumes when Watch Now is active again.
        .onChange(of: model.isActive, initial: true) { _, active in
            drift = active
        }
    }

    /// Repeating Ken Burns pan while the hero is active; a one-shot (non-repeating) curve when it isn't,
    /// so toggling `drift` off settles once and the animation stops rather than looping under a cover.
    private var kenBurnsAnimation: Animation {
        model.isActive
            ? .easeInOut(duration: Theme.Hero.kenBurnsDuration).repeatForever(autoreverses: true)
            : .easeInOut(duration: Theme.Hero.kenBurnsDuration)
    }
}

// MARK: - Backdrop image

private struct HeroBackdrop: View {
    let url: URL?

    var body: some View {
        RemoteImage(url: url, targetSize: Theme.Hero.backdropTargetSize, contentMode: .fill) {
            Color(white: 0.04)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
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
