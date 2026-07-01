import SwiftUI

/// Shared carousel state for the Watch Now hero, hoisted out of the view so the **pinned backdrop**
/// (`HeroBackdropLayer`) and the **scrolling overlay** (`HeroOverlay`) page as a single unit while
/// living in different parts of the view tree: the backdrop sits behind the scroll view, the
/// logo/buttons/dots scroll up over it. Both read this one model, so a page-slide or auto-advance
/// moves the image and the text together.
///
/// Owns the inline trailer controller, the auto-advance timer logic, neighbour prefetch, and the page
/// index — the shared carousel state both hero layers drive.
@MainActor
@Observable
final class HeroCarouselModel {
    /// Featured titles, set by `WatchNowView` from the view model.
    var items: [MetaPreview] = []
    /// False while a detail screen / stream picker covers Watch Now, so the trailer tears down instead
    /// of decoding underneath. The auto-advance timer also stands down.
    var isActive = true
    /// Whether the hero is still on screen (hasn't scrolled off the top under the content sheet), driven
    /// from the scroll clock via `setHeroVisible(_:)`. Distinct from `isActive`: covering the hero tears
    /// the player fully down, whereas scrolling it off merely pauses playback so scrolling back resumes
    /// instantly.
    private(set) var isHeroVisible = true
    /// Set by the overlay while a hero control holds focus, so the timer doesn't shift content under an
    /// aimed button (Apple TV behaviour).
    var isControlFocused = false

    private(set) var index = 0
    /// Last paging direction, so the backdrop and the text/logo slide the same way on a page change.
    private(set) var forward = true

    /// Inline trailer for the current featured title (Trailerio). Plays once, then pages on.
    let trailer = TrailerPlaybackController()

    var currentItem: MetaPreview? {
        items.indices.contains(index) ? items[index] : nil
    }

    var canPage: Bool { items.count > 1 }

    /// Item-reset: when the feed changes, jump back to the first title and warm its neighbours.
    func resetToFirst() {
        index = 0
        prefetchNeighbors()
    }

    /// Single place that moves the carousel, with wraparound + slide. Used by both manual edge-button
    /// paging (step ±1) and auto-advance (step +1). The `withAnimation` transaction covers every view
    /// that reads `index`/`forward`, so the pinned backdrop and the scrolling text slide together.
    func advance(by step: Int) {
        guard items.count > 1 else { return }
        forward = step > 0
        withAnimation(.easeInOut(duration: Theme.Hero.pageSlideDuration)) {
            index = (index + step + items.count) % items.count
        }
    }

    /// Rotates featured items on a timer, paused while the user is focused on a hero control, a trailer
    /// is mid-play (a playing trailer pages on its own when it ends, so the timer stands down), or the
    /// hero has scrolled off screen (nothing should shift under the content sheet where it isn't seen).
    func autoAdvance() async {
        guard items.count > 1 else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Theme.Hero.autoAdvanceInterval))
            if Task.isCancelled { break }
            if isControlFocused || trailer.isReady || !isHeroVisible { continue }
            advance(by: 1)
        }
    }

    /// Reflect the hero's on-screen visibility as the content sheet scrolls over it. When the hero
    /// scrolls off the top its trailer is no longer part of the visible screen, so pause playback
    /// (keeping the player warm so scrolling back resumes instantly); resume when it returns. A no-op
    /// while the hero is inactive — a covering detail / stream picker has already torn the player down.
    func setHeroVisible(_ visible: Bool) {
        guard visible != isHeroVisible else { return }
        isHeroVisible = visible
        guard isActive else { return }
        if visible {
            trailer.play()
        } else {
            trailer.pause()
        }
    }

    /// Load + autoplay the current title's trailer (no loop with >1 item — it pages on when the trailer
    /// ends). Tears the previous player down first so the old video doesn't render over the new page.
    func loadTrailer() async {
        guard isActive, let meta = currentItem else { trailer.teardown(); return }
        trailer.teardown()
        trailer.loops = items.count <= 1
        trailer.onPlaybackEnded = { [weak self] in self?.advance(by: 1) }
        let candidates = await TrailerSource.candidates(type: meta.type, id: meta.id)
        guard !Task.isCancelled, !candidates.isEmpty else { return }
        trailer.load(candidates)
        // Only begin playing if the hero is actually on screen — a title that loads (e.g. via
        // auto-advance) while scrolled away stays paused until the hero scrolls back into view.
        if isHeroVisible { trailer.autoplay() }
    }

    /// Warm BOTH neighbours so a page-slide in either direction shows the real image immediately.
    func prefetchNeighbors() {
        guard items.count > 1 else { return }
        for offset in [1, -1] {
            let neighbor = (index + offset + items.count) % items.count
            guard let url = items[neighbor].background.flatMap(URL.init(string:)) else { continue }
            Task { await ImageLoader.shared.prefetch(url: url, targetSize: Theme.Hero.backdropTargetSize) }
        }
    }
}
