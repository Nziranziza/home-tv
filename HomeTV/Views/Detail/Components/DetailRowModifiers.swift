import SwiftUI

extension View {
    /// Reports `zone == .content` while focused, when this view is part of the TOP content row. Crossing
    /// into/out of it (from/to the hero) drives the full-viewport scroll. Applied only to top-row items so
    /// navigating among lower shelves doesn't re-trigger the scroll; a no-op otherwise.
    @ViewBuilder
    func contentZone(_ active: Bool, _ binding: FocusState<MetaDetailView.Zone?>.Binding) -> some View {
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
    func detailRowScroll() -> some View {
        scrollClipDisabled()
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .horizontal)
    }
}
