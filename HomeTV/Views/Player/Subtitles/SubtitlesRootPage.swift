import SwiftUI

/// The Subtitles menu's top level: On and Off, then the Language and Style sub-menus.
struct SubtitlesRootPage: View {
    let subtitles: PlayerSubtitles
    let focus: FocusState<Int?>.Binding
    let onOpen: (SubtitlesMenuPage) -> Void

    var body: some View {
        VStack(spacing: 0) {
            PlayerMenuRow(title: "On", isChecked: subtitles.isOn, action: subtitles.turnOn)
                .focused(focus, equals: 0)
            PlayerMenuRow(title: "Off", isChecked: !subtitles.isOn, action: subtitles.turnOff)
                .focused(focus, equals: 1)
            PlayerMenuDivider()
            PlayerMenuRow(title: "Language", value: subtitles.trackName, accessory: .chevron) { onOpen(.language) }
                .focused(focus, equals: 2)
            PlayerMenuRow(title: "Style", value: subtitles.activeStyleName, accessory: .chevron) { onOpen(.style) }
                .focused(focus, equals: 3)
        }
        .padding(.horizontal, PlayerMenuMetrics.rowInset)
        .padding(.top, PlayerMenuMetrics.topPadding)
        .padding(.bottom, PlayerMenuMetrics.bottomPadding)
    }
}
