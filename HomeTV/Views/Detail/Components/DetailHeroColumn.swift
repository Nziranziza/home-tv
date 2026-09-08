import SwiftUI

/// The State-A hero's content column: title → chips → description → facts → actions, bottom-anchored to
/// the lower-left inside the hero frame so the action row settles near the bottom safe area, with an
/// optional `trailing` block (the title hero's credits) sharing that bottom baseline on the right.
///
/// Shared by the title detail hero and the episode hero so both own the same rhythm, gutter, and collapse
/// fade — the two previously assembled this container by hand and drifted apart. Callers supply only the
/// rows; the column owns the spacing, the horizontal gutter, the bottom inset, the fade, and the focus
/// section.
struct DetailHeroColumn<Content: View, Trailing: View>: View {
    let scroll: DetailScrollState
    @ViewBuilder var content: () -> Content
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        // The collapse fade is applied by the `HeroCollapseFade` child, which is what reads
        // `scroll.heroOpacity` — so a scroll tick re-renders only that wrapper rather than rebuilding the
        // column. Modifier order is the same as when each hero applied the opacity itself: on the padded
        // stack, inside `focusSection()`.
        HeroCollapseFade(scroll: scroll) {
            ZStack(alignment: .bottomLeading) {
                // Credits share the action row's bottom baseline: bottom-trailing, right edge at the
                // right-margin token (leftInset 86 + 74 trailing = 160 from the right). Grows up.
                trailing()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

                VStack(alignment: .leading, spacing: Theme.Detail.heroColumnSpacing) {
                    content()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.horizontal, Theme.Detail.leftInset)
            .padding(.bottom, Theme.Detail.heroColumnBottomPadding)
        }
        .focusSection()
    }
}

extension DetailHeroColumn where Trailing == EmptyView {
    /// A column with no trailing block — the episode hero, which carries no credits.
    init(scroll: DetailScrollState, @ViewBuilder content: @escaping () -> Content) {
        self.init(scroll: scroll, content: content, trailing: { EmptyView() })
    }
}
