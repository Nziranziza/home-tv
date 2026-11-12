import SwiftUI
import UIKit

/// The Subtitles menu, opened from the Subtitles button. Its sub-menus replace the panel's content in
/// place; Menu backs out one level (`PlayerModel.handleExit`). Each level opens on its first row.
struct SubtitlesMenu: View {
    let model: PlayerModel
    let page: SubtitlesMenuPage
    @FocusState private var focusedRow: Int?
    @Environment(\.openURL) private var openURL

    var body: some View {
        PlayerMenuPanel(title: page.title) {
            switch page {
            case .root:
                SubtitlesRootPage(subtitles: model.subtitles, focus: $focusedRow, onOpen: model.showSubtitlesMenu)
            case .language:
                SubtitlesLanguagePage(subtitles: model.subtitles, focus: $focusedRow)
            case .style:
                SubtitlesStylePage(subtitles: model.subtitles, focus: $focusedRow, onManageStyles: manageStyles)
            }
        }
        // Disabling the Subtitles button doesn't move focus off it, so the menu claims it.
        .defaultFocus($focusedRow, 0)
        .onAppear { focusedRow = 0 }
        .onChange(of: page) { focusedRow = 0 }
    }

    /// Caption styles are edited in Settings. Apps can only open its top level, not the Subtitles page.
    private func manageStyles() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        model.pauseForSettings()
        openURL(url)
    }
}
