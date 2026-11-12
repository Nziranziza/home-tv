import SwiftUI

/// The system caption styles, then Manage Styles, which opens Settings. Scrolls past eight rows, like the
/// Language page.
struct SubtitlesStylePage: View {
    let subtitles: PlayerSubtitles
    let focus: FocusState<Int?>.Binding
    let onManageStyles: () -> Void

    private static let visibleRows: CGFloat = 8

    var body: some View {
        let top = PlayerMenuMetrics.topPadding
        let bottom = PlayerMenuMetrics.bottomPadding
        let rowsHeight = CGFloat(subtitles.styles.count + 1) * PlayerMenuRow.height + PlayerMenuDivider.height
        ScrollView {
            VStack(spacing: 0) {
                ForEach(subtitles.styles.enumerated(), id: \.element.id) { index, style in
                    PlayerMenuRow(title: style.name, isChecked: style.id == subtitles.activeStyleID) {
                        subtitles.selectStyle(style)
                    }
                    .focused(focus, equals: index)
                }
                PlayerMenuDivider()
                PlayerMenuRow(title: "Manage Styles", accessory: .gear, action: onManageStyles)
                    .focused(focus, equals: subtitles.styles.count)
            }
            .padding(.horizontal, PlayerMenuMetrics.rowInset)
            .padding(.top, top)
            .padding(.bottom, bottom)
        }
        .scrollIndicators(.hidden)
        .frame(height: min(top + rowsHeight + bottom, top + Self.visibleRows * PlayerMenuRow.height))
    }
}
