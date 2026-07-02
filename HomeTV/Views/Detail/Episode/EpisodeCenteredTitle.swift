import SwiftUI

/// The episode title, centered at the top of the episode screen's scrolling content (the browse-state
/// counterpart to the hero's title). An in-flow item that scrolls with the page and fades in on the
/// collapse clock (`scroll.logoReveal`) — the episode analogue of `DetailCenteredLogo`, but always text
/// (an episode has no logo art of its own).
struct EpisodeCenteredTitle: View {
    let title: String
    let scroll: DetailScrollState

    var body: some View {
        Text(title)
            .font(.system(size: 52, weight: .bold))
            .foregroundStyle(Theme.Color.primaryText)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, Theme.Detail.leftInset)
            .padding(.top, 45)
            .frame(height: DetailLayout.browseTopInset, alignment: .top)
            .opacity(scroll.logoReveal)
    }
}
