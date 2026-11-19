import SwiftUI
import UIKit

/// The Subtitles menu, opened from the Subtitles button. Its sub-menus replace the panel's content in
/// place; Menu backs out one level (`PlayerModel.handleExit`). Each level opens on its first row.
struct SubtitlesMenu: View {
    let model: PlayerModel
    let page: SubtitlesMenuPage
    @FocusState private var focusedRow: SubtitlesMenuRow?
    @Environment(\.openURL) private var openURL

    /// Back from a language's files, that language's row.
    private var returnRow: SubtitlesMenuRow? {
        guard page == .language, case .files(let languageCode, _) = model.previousSubtitlesMenu,
              model.subtitles.fileLanguages.contains(where: { $0.languageCode == languageCode }) else { return nil }
        return .language(languageCode)
    }

    /// The row a page opens on.
    private var firstRow: SubtitlesMenuRow? {
        let subtitles = model.subtitles
        switch page {
        case .root, .style:
            return .position(0)
        case .language:
            return subtitles.streamOptions.first.map { .track($0.id) }
                ?? subtitles.fileLanguages.first.map { .language($0.languageCode) }
        case .files(let languageCode, _):
            return subtitles.files(in: languageCode).first.map { .track($0.id) }
        }
    }

    private var listHeight: CGFloat {
        if case .files(let languageCode, _) = page {
            return SubtitlesFilesPage.rowsHeight(model.subtitles, languageCode: languageCode)
        }
        return SubtitlesLanguagePage.rowsHeight(model.subtitles)
    }

    var body: some View {
        PlayerMenuPanel(title: page.title) {
            switch page {
            case .root:
                SubtitlesRootPage(subtitles: model.subtitles, focus: $focusedRow, onOpen: model.showSubtitlesMenu)
            case .language, .files:
                PlayerMenuScrollList(rowsHeight: listHeight) {
                    if case .files(let languageCode, _) = page {
                        SubtitlesFilesPage(subtitles: model.subtitles, languageCode: languageCode, focus: $focusedRow)
                    } else {
                        SubtitlesLanguagePage(
                            subtitles: model.subtitles,
                            focus: $focusedRow,
                            returnRow: returnRow,
                            onOpen: model.showSubtitlesMenu
                        )
                    }
                }
            case .style:
                SubtitlesStylePage(subtitles: model.subtitles, focus: $focusedRow, onManageStyles: manageStyles)
            }
        }
        // Disabling the Subtitles button doesn't move focus off it, so the menu claims it.
        .defaultFocus($focusedRow, firstRow)
        .onAppear { focusedRow = firstRow }
        .onChange(of: page) { focusedRow = returnRow ?? firstRow }
    }

    /// Caption styles are edited in Settings. Apps can only open its top level, not the Subtitles page.
    private func manageStyles() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        model.pauseForSettings()
        openURL(url)
    }
}
