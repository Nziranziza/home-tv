import SwiftUI

/// A menu page's rows, scrolling past eight rows' height. The last visible row fades while there are more
/// below it.
struct PlayerMenuScrollList<Content: View>: View {
    /// The rows' total height.
    let rowsHeight: CGFloat
    @ViewBuilder let content: Content
    @State private var hasMoreBelow = false

    private static var visibleRows: CGFloat { 8 }

    var body: some View {
        let top = PlayerMenuMetrics.topPadding
        let bottom = PlayerMenuMetrics.bottomPadding
        ScrollView {
            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, PlayerMenuMetrics.rowInset)
            .padding(.top, top)
            .padding(.bottom, bottom)
        }
        .scrollIndicators(.hidden)
        .frame(height: min(top + rowsHeight + bottom, top + Self.visibleRows * PlayerMenuRow.height))
        .mask {
            VStack(spacing: 0) {
                Rectangle()
                LinearGradient(
                    colors: [.black, .black.opacity(hasMoreBelow ? 0.6 : 1)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: PlayerMenuRow.height)
            }
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height - 1
        } action: { _, more in
            hasMoreBelow = more
        }
    }
}
