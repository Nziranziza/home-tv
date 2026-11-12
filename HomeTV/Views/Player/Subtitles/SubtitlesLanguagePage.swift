import SwiftUI

/// The stream's subtitle languages. Past eight rows the list scrolls, and the last visible row fades
/// while there are more below it.
struct SubtitlesLanguagePage: View {
    let subtitles: PlayerSubtitles
    let focus: FocusState<Int?>.Binding
    @State private var hasMoreBelow = false

    private static let visibleRows: CGFloat = 8

    var body: some View {
        let top = PlayerMenuMetrics.topPadding
        let bottom = PlayerMenuMetrics.bottomPadding
        let rowsHeight = CGFloat(subtitles.options.count) * PlayerMenuRow.height
        ScrollView {
            VStack(spacing: 0) {
                ForEach(subtitles.options.enumerated(), id: \.element.id) { index, option in
                    PlayerMenuRow(title: option.name, isChecked: option.id == subtitles.track?.id) {
                        subtitles.select(option)
                    }
                    .focused(focus, equals: index)
                }
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
