import SwiftUI

// MARK: - Section header (dark background, Apple Title Case)

struct DetailSectionHeader: View {
    let title: String
    /// Left guide for the header. Defaults to the global content margin; the About/Information block
    /// passes its own (slightly tighter) guide so the header aligns with that block's card text.
    var leadingInset: CGFloat = Theme.Detail.leftInset
    /// Browse-chrome opacity: section labels belong to State B. They're hidden in State A (so the bare
    /// trailer card peeks at the bottom with no header above it) and fade in with the collapse.
    @Environment(\.detailChromeOpacity) private var chromeOpacity

    var body: some View {
        // The card/posters rise with the content without fading; only this label fades in.
        Text(title)
            .font(.system(size: 30, weight: .semibold))
            // Opaque secondary grey (~RGB 153) so it reads consistently dim — white@opacity alpha-blends
            // with the bright blurred backdrop and comes out too light.
            .foregroundStyle(Color(white: 0.6))
            .padding(.leading, leadingInset)
            .opacity(chromeOpacity)
    }
}

private struct DetailChromeOpacityKey: EnvironmentKey {
    static let defaultValue: Double = 1
}

extension EnvironmentValues {
    /// 0 in State A → 1 in State B; drives the browse-chrome (section headers) fade-in.
    var detailChromeOpacity: Double {
        get { self[DetailChromeOpacityKey.self] }
        set { self[DetailChromeOpacityKey.self] = newValue }
    }
}

