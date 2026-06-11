import SwiftUI

// MARK: - Section header (dark background, Apple Title Case)

struct DetailSectionHeader: View {
    let title: String
    /// Left guide for the header. Defaults to the global content margin; the About/Information block
    /// passes its own (slightly tighter) guide so the header aligns with that block's card text.
    var leadingInset: CGFloat = Theme.Detail.leftInset
    /// The collapse clock. Section labels belong to State B: they're hidden in State A (so the bare
    /// trailer card peeks at the bottom with no header above it) and fade in with the collapse. Read
    /// directly here (a leaf) so only the headers re-render on scroll — never the rows beneath them.
    let scroll: DetailScrollState

    var body: some View {
        // The card/posters rise with the content without fading; only this label fades in.
        Text(title)
            .font(.system(size: 30, weight: .semibold))
            // Opaque secondary grey (~RGB 153) so it reads consistently dim — white@opacity alpha-blends
            // with the bright blurred backdrop and comes out too light.
            .foregroundStyle(Color(white: 0.6))
            .padding(.leading, leadingInset)
            .opacity(scroll.logoReveal)
    }
}
