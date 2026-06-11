import SwiftUI

/// The title logo, centered at the top of the scrolling content (above the first content row). It's an
/// in-flow item — it scrolls with the page, not pinned. It fills the `browseTopInset` band that rests at
/// the top in the browse state, and fades on the collapse clock (`scroll.logoReveal`) so it never paints
/// over the hero in State A (where this band is pulled up behind the hero).
struct DetailCenteredLogo: View {
    let model: MetaDetailModel
    let scroll: DetailScrollState

    var body: some View {
        centeredLogoArt
            .frame(width: 228, height: 99)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 45)
            .frame(height: DetailLayout.browseTopInset, alignment: .top)
            .opacity(scroll.logoReveal)
    }

    @ViewBuilder
    private var centeredLogoArt: some View {
        if let url = model.vm.displayLogoURL {
            RemoteImage(url: url, targetSize: CGSize(width: 800, height: 220), contentMode: .fit) {
                centeredLogoFallback
            }
            .accessibilityLabel(model.meta?.name ?? model.fallbackTitle)
        } else {
            centeredLogoFallback
        }
    }

    private var centeredLogoFallback: some View {
        Text(model.meta?.name ?? model.fallbackTitle)
            .font(.system(size: 34, weight: .heavy))
            .foregroundStyle(Theme.Color.primaryText)
            .multilineTextAlignment(.center)
            .lineLimit(2)
    }
}
