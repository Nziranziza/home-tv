import SwiftUI

/// The Search screen's page scroll, shared by the Browse and results states so both sit at the same
/// margins and scroll identically.
///
/// Edge-to-edge horizontally — each section applies its own `Theme.Row.contentInset`, matching Watch
/// Now — with the viewport running all the way to the bottom safe area. There is no bottom bar to
/// clear (with `.sidebarAdaptable` the tab bar is a left sidebar), so the only bottom inset is the
/// small `pageBottomInset` *inside* the scroll, which lets the last row's focus lift clear the
/// overscan edge without leaving a dead band under it. Deliberately left clipping: each row disables
/// its own clip for the focus lift, and letting the page scroll draw outside its bounds is what put
/// the content over the search header.
struct SearchPageScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            content
                .padding(.bottom, Theme.Search.pageBottomInset)
        }
        .scrollIndicators(.hidden)
        .pageHorizontalInsets()
    }
}
