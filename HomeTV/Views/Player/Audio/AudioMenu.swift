import SwiftUI

/// The Audio menu, opened from the Audio button: Enhance Dialogue and Reduce Loud Sounds, then the stream's
/// audio tracks. Enhance Dialogue's choices replace it in place; Menu backs out (`PlayerModel.handleExit`).
struct AudioMenu: View {
    let model: PlayerModel
    let page: AudioMenuPage
    @FocusState private var focusedRow: AudioMenuRow?

    private var audio: PlayerAudio { model.audio }

    /// The row a page opens on: the first, else the first track while the adjustments are unavailable.
    /// Enhance Dialogue's choices open on the current one; back from them, Enhance Dialogue.
    private var firstRow: AudioMenuRow? {
        switch page {
        case .root where model.previousAudioMenu == .enhanceDialogue:
            .enhanceDialogue
        case .root:
            audio.canAdjust ? .enhanceDialogue : audio.options.first.map { .track($0.id) }
        case .enhanceDialogue:
            .dialogue(audio.adjustments.dialogue)
        }
    }

    private var rowsHeight: CGFloat {
        switch page {
        case .root: AudioMenuRootPage.rowsHeight(audio)
        case .enhanceDialogue: AudioMenuDialoguePage.rowsHeight
        }
    }

    var body: some View {
        PlayerMenuPanel(title: page.title) {
            // One scroll view for both pages: a new one isn't laid out in time to take focus on Menu.
            PlayerMenuScrollList(rowsHeight: rowsHeight) {
                switch page {
                case .root:
                    AudioMenuRootPage(audio: audio, focus: $focusedRow, onOpen: model.showAudioMenu)
                case .enhanceDialogue:
                    AudioMenuDialoguePage(audio: audio, focus: $focusedRow)
                }
            }
        }
        // Disabling the Audio button doesn't move focus off it, so the menu claims it.
        .defaultFocus($focusedRow, firstRow)
        .onAppear { focusedRow = firstRow }
        .onChange(of: page) { focusedRow = firstRow }
    }
}
