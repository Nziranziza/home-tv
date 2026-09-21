import SwiftUI

/// The Search screen's page scroll, shared by the Browse and results states so both sit at the same
/// margins and scroll identically.
///
/// Edge-to-edge horizontally — each section applies its own `Theme.Row.contentInset`, matching Watch
/// Now — with the vertical safe area kept so content clears the tab bar. Deliberately left clipping:
/// each row disables its own clip for the focus lift, and letting the page scroll draw outside its
/// bounds is what put the content over the search header.
struct SearchPageScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            content
                .padding(.bottom, Theme.WatchNow.bottomPadding)
        }
        .scrollIndicators(.hidden)
        .pageHorizontalInsets()
    }
}
