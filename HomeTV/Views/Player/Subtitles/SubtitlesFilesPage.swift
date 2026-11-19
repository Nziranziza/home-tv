import SwiftUI

/// Every add-on file in one language, best match to the stream first, each with its release in grey so
/// the one made for this copy can be found. Rows only; `SubtitlesMenu` scrolls them.
struct SubtitlesFilesPage: View {
    let subtitles: PlayerSubtitles
    let languageCode: String?
    let focus: FocusState<SubtitlesMenuRow?>.Binding

    static func rowsHeight(_ subtitles: PlayerSubtitles, languageCode: String?) -> CGFloat {
        subtitles.files(in: languageCode).reduce(0) {
            $0 + ($1.detail == nil ? PlayerMenuRow.height : PlayerMenuRow.heightWithValue)
        }
    }

    var body: some View {
        ForEach(subtitles.files(in: languageCode)) { option in
            PlayerMenuRow(title: option.name, value: option.detail, isChecked: option.id == subtitles.track?.id) {
                subtitles.select(option)
            }
            .focused(focus, equals: .track(option.id))
        }
    }
}
