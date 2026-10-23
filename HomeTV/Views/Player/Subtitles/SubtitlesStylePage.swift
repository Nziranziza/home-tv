import SwiftUI

/// The system caption styles, then Manage Styles, which opens Settings.
struct SubtitlesStylePage: View {
    let subtitles: PlayerSubtitles
    let focus: FocusState<Int?>.Binding
    let onManageStyles: () -> Void

    var body: some View {
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
        .padding(.top, PlayerMenuMetrics.topPadding)
        .padding(.bottom, PlayerMenuMetrics.bottomPadding)
    }
}
