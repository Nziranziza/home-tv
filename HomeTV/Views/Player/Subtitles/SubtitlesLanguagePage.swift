import SwiftUI

/// The stream's subtitle languages, then below a divider each language the add-ons have files in, which
/// opens the page of its files. Rows only; `SubtitlesMenu` scrolls them.
struct SubtitlesLanguagePage: View {
    let subtitles: PlayerSubtitles
    let focus: FocusState<SubtitlesMenuRow?>.Binding
    /// The row focus returns to, backing out of a language's files.
    var returnRow: SubtitlesMenuRow?
    let onOpen: (SubtitlesMenuPage) -> Void
    /// tvOS rejects a focus request here and lands on the first focusable row, so on return every other
    /// row is briefly disabled.
    @State private var isReturning = true

    static func rowsHeight(_ subtitles: PlayerSubtitles) -> CGFloat {
        let streamRows = subtitles.streamOptions.count
        let languages = subtitles.fileLanguages.count
        return CGFloat(streamRows) * PlayerMenuRow.height
            + CGFloat(languages) * PlayerMenuRow.heightWithValue
            + (streamRows > 0 && languages > 0 ? PlayerMenuDivider.height : 0)
    }

    var body: some View {
        let streamOptions = subtitles.streamOptions
        let languages = subtitles.fileLanguages
        ForEach(streamOptions) { option in
            PlayerMenuRow(title: option.name, isChecked: option.id == subtitles.track?.id) {
                subtitles.select(option)
            }
            .focused(focus, equals: .track(option.id))
            .disabled(isLocked(.track(option.id)))
        }
        if !streamOptions.isEmpty, !languages.isEmpty { PlayerMenuDivider() }
        ForEach(languages) { language in
            PlayerMenuRow(
                title: language.name,
                value: Self.count(language.files.count),
                isChecked: language.files.contains { $0.id == subtitles.track?.id },
                accessory: .chevron
            ) {
                onOpen(.files(languageCode: language.languageCode, name: language.name))
            }
            .focused(focus, equals: .language(language.languageCode))
            .disabled(isLocked(.language(language.languageCode)))
        }
        .task {
            guard returnRow != nil else { return }
            try? await Task.sleep(for: .milliseconds(300))
            isReturning = false
        }
    }

    private func isLocked(_ row: SubtitlesMenuRow) -> Bool {
        guard let returnRow, isReturning else { return false }
        return row != returnRow
    }

    private static func count(_ files: Int) -> String {
        files == 1 ? "1 File" : "\(files) Files"
    }
}
