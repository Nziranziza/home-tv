import SwiftUI

/// The Audio menu, opened from the Audio button: the stream's audio tracks. Past eight rows it scrolls.
/// Opens on its first row, like the Subtitles menu.
struct AudioMenu: View {
    let audio: PlayerAudio
    @FocusState private var focusedRow: Int?

    private static let visibleHeight: CGFloat = 8 * PlayerMenuRow.height

    var body: some View {
        let top = PlayerMenuMetrics.topPadding
        let bottom = PlayerMenuMetrics.bottomPadding
        let rowsHeight = audio.options.reduce(0) { height, option in
            height + (option.detail == nil ? PlayerMenuRow.height : PlayerMenuRow.heightWithValue)
        }
        PlayerMenuPanel(title: "Audio Track") {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(audio.options.enumerated(), id: \.element.id) { index, option in
                        PlayerMenuRow(
                            title: option.title,
                            value: option.detail,
                            isChecked: option.id == audio.track?.id
                        ) {
                            audio.select(option)
                        }
                        .focused($focusedRow, equals: index)
                    }
                }
                .padding(.horizontal, PlayerMenuMetrics.rowInset)
                .padding(.top, top)
                .padding(.bottom, bottom)
            }
            .scrollIndicators(.hidden)
            .frame(height: min(top + rowsHeight + bottom, top + Self.visibleHeight))
        }
        // Disabling the Audio button doesn't move focus off it, so the menu claims it.
        .defaultFocus($focusedRow, 0)
        .onAppear { focusedRow = 0 }
    }
}
