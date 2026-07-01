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

    /// The single shared paging driver: sub-page slide progress in page-width units, read by BOTH hero
    /// layers so they translate as one rigid surface. `0` at rest; a page springs it to `±1` and then an
    /// instant recenter snaps it back to `0` (see `advance(by:)`). Both layers position their window
    /// slots through `windowOffset(slot:width:)`, so they apply one identical offset and cannot desync.
    private(set) var slide: CGFloat = 0
    /// True while a page-slide is animating, so a second page press (or an auto-advance tick) is dropped
    /// mid-slide rather than corrupting the recenter bookkeeping. Also gates the trailer off during the
    /// slide so a playing video doesn't sit static over the moving stills.
    private(set) var isPaging = false

    /// Inline trailer for the current featured title (Trailerio). Plays once, then pages on.
    let trailer = TrailerPlaybackController()

    var currentItem: MetaPreview? {
        items.indices.contains(index) ? items[index] : nil
    }

    var canPage: Bool { items.count > 1 }

    /// The item at a window slot offset (`-1` previous / `0` current / `+1` next) from the current index,
    /// wrapped. This is the 3-slot window both hero layers render so a page-slide always has the
    /// neighbour it's gliding toward already on-screen and cached.
    func windowItem(_ slot: Int) -> MetaPreview? {
        guard !items.isEmpty else { return nil }
        return items[(index + slot + items.count) % items.count]
    }

    /// Horizontal offset (in points) for a window slot at the current `slide`. Both hero layers position
    /// every slot through this one function, so the backdrop still and the text translate by the exact
    /// same amount — the shared driver made literal. At rest (`slide == 0`) slot 0 sits centred and ±1 sit
    /// one viewport off each edge; as `slide` springs to `±1` the whole trio glides one page.
    func windowOffset(slot: Int, width: CGFloat) -> CGFloat {
        (CGFloat(slot) - slide) * width
    }

    /// The page currently occupying the viewport centre, following the in-flight `slide` so the page dots
    /// track the motion (flipping as the new page crosses the halfway point) rather than snapping only at
    /// the end when `index` recenters. Equal to `index` at rest and after a page settles.
    var displayedIndex: Int {
        guard !items.isEmpty else { return 0 }
        return (index + Int(slide.rounded()) + items.count) % items.count
    }

    /// Item-reset: when the feed changes, jump back to the first title and warm its neighbours. Also
    /// clears any in-flight slide so a feed change (or a return from a covering screen that cancelled the
    /// slide animation before its completion fired) can never leave the strip off-centre or `isPaging`
    /// stuck.
    func resetToFirst() {
        index = 0
        slide = 0
        isPaging = false
        prefetchNeighbors()
    }

    /// Single place that moves the carousel, with wraparound. Used by both manual edge-button paging
    /// (step ±1) and auto-advance (step +1). Springs the shared `slide` driver one page (`0 → ±step`) so
    /// the 3-slot window in both hero layers glides as one surface, then — on completion — recenters
    /// instantly: bumps `index` and resets `slide` to 0 inside a transaction that disables animation. The
    /// recenter is invisible because the destination slot already shows the destination title.
    func advance(by step: Int) {
        guard items.count > 1, !isPaging else { return }
        // Capture the feed identity: the ~0.5s slide can outlast a feed change, whose `.task(id:)` calls
        // `resetToFirst()`. If the completion then fires on a different (or empty) feed, drop it — applying
        // the recenter would overwrite that reset and, on an empty feed, divide by a zero count.
        let pagingItems = items.map(\.id)
        isPaging = true
        // Silence the outgoing trailer for the duration of the slide; the item-change task tears it down
        // and reloads the new title's trailer once the page settles.
        if trailer.isReady { trailer.pause() }
        withAnimation(Theme.Hero.pageSlideSpring) {
            slide = CGFloat(step)
        } completion: {
            guard self.items.map(\.id) == pagingItems else { self.isPaging = false; return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                self.index = (self.index + step + self.items.count) % self.items.count
                self.slide = 0
            }
            self.isPaging = false
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
