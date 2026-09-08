import SwiftUI

extension View {
    /// Reports `zone == .content` while focused, when this view is part of the TOP content row. Crossing
    /// into/out of it (from/to the hero) drives the full-viewport scroll. Applied only to top-row items so
    /// navigating among lower shelves doesn't re-trigger the scroll; a no-op otherwise.
    @ViewBuilder
    func contentZone(_ active: Bool, _ binding: FocusState<DetailZone?>.Binding) -> some View {
        if active {
            focused(binding, equals: .content)
        } else {
            self
        }
    }

    /// Standard treatment for a detail row's horizontal `ScrollView`: don't clip the cards' focus lift,
    /// and lay the row out to the physical screen edges so its `leftInset` is measured from the same edge
    /// as the hero. (A nested ScrollView otherwise re-introduces the horizontal safe-area inset, leaving
    /// the rows pushed in relative to the hero column.)
    /// Standard treatment for a detail row's horizontal `ScrollView`.
    ///
    /// `clipsToBounds` (default `true`): clip the row to its bounds. Leaving the clip off (the old blanket
    /// `scrollClipDisabled()`) let a shelf's cards draw into the neighbouring shelf's region, and the focus
    /// engine then mis-resolved "next item down" during a fast flick — snapping focus back to the previous
    /// shelf for a frame before advancing. Clipping removes that overlap; the focus lift stays visible
    /// because each content row reserves enough vertical padding for it to grow into. Pass `false` for the
    /// season selector, which must overflow its fixed-height header slot upward (see `detailRowHeader`).
    func detailRowScroll(clipsToBounds: Bool = true) -> some View {
        scrollClipDisabled(!clipsToBounds)
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .horizontal)
            // Cancel the overflow `detailRowContentPadding` added inside, so the enlarged clip rect
            // costs the layout nothing (see `Theme.Detail.rowFocusOverflowTop` / `…Bottom`).
            .padding(.top, clipsToBounds ? -Theme.Detail.rowFocusOverflowTop : 0)
            .padding(.bottom, clipsToBounds ? -Theme.Detail.rowFocusOverflowBottom : 0)
    }

    /// Vertical padding for a clipped row's scroll content: the row's own breathing room plus the shared
    /// focus overflow. Clipping the row to its bounds cut a focused card's drop shadow off flat at the
    /// bottom edge — the lift fitted, the shadow beneath it didn't. Padding the content here and
    /// un-padding the scroll view in `detailRowScroll` grows the clip rect around the cards without
    /// moving them or changing the height the row occupies.
    func detailRowContentPadding(_ base: CGFloat) -> some View {
        padding(.top, base + Theme.Detail.rowFocusOverflowTop)
            .padding(.bottom, base + Theme.Detail.rowFocusOverflowBottom)
    }

    /// Places a content row's header (a section label or the season selector) into a fixed-height slot,
    /// bottom-anchored. The slot's height is what the layout reserves, so the cards below — and the hero
    /// peek they form — sit at the same place no matter how tall the header's content is. Content taller
    /// than the slot (e.g. the season tabs vs a one-line label) keeps its natural size via `fixedSize`
    /// and overflows *upward* out of the slot (drawn, not clipped — rows already disable scroll clipping),
    /// so it never pushes the cards down. This is the single contract that keeps the episode peek
    /// identical for one season or eight, and leaves the collapse animation untouched (the cards never
    /// move with the header's height).
    func detailRowHeader() -> some View {
        fixedSize(horizontal: false, vertical: true)
            .frame(height: Theme.Detail.rowHeaderHeight, alignment: .bottom)
    }
}
