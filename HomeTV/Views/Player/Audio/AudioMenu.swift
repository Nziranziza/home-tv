import SwiftUI

/// The Audio menu, opened from the Audio button: Enhance Dialogue and Reduce Loud Sounds, then the stream's
/// audio tracks. Enhance Dialogue's choices replace it in place; Menu backs out (`PlayerModel.handleExit`).
struct AudioMenu: View {
    let model: PlayerModel
    let page: AudioMenuPage
    @FocusState private var focusedRow: AudioMenuRow?

    private static let unavailable = "Not available for this audio"

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

    var body: some View {
        PlayerMenuPanel(title: page.title) {
            // One scroll view for both pages: a new one isn't laid out in time to take focus on Menu.
            PlayerMenuScrollList(rowsHeight: page == .root ? rootRowsHeight : 3 * PlayerMenuRow.height) {
                switch page {
                case .root: rootRows
                case .enhanceDialogue: dialogueRows
                }
            }
        }
        // Disabling the Audio button doesn't move focus off it, so the menu claims it.
        .defaultFocus($focusedRow, firstRow)
        .onAppear { focusedRow = firstRow }
        .onChange(of: page) { focusedRow = firstRow }
    }

    private var rootRowsHeight: CGFloat {
        let tracks = audio.options.reduce(0) { height, option in
            height + (option.detail == nil ? PlayerMenuRow.height : PlayerMenuRow.heightWithValue)
        }
        let reduceLoudSounds = audio.canAdjust ? PlayerMenuRow.height : PlayerMenuRow.heightWithValue
        return PlayerMenuRow.heightWithValue + reduceLoudSounds + PlayerMenuDivider.height
            + PlayerMenuSectionHeader.height + tracks
    }

    @ViewBuilder private var rootRows: some View {
        let canAdjust = audio.canAdjust
        PlayerMenuRow(
            title: "Enhance Dialogue",
            value: canAdjust ? audio.adjustments.dialogue.title : Self.unavailable,
            accessory: canAdjust ? .chevron : .none
        ) {
            model.showAudioMenu(.enhanceDialogue)
        }
        .disabled(!canAdjust)
        .focused($focusedRow, equals: .enhanceDialogue)
        PlayerMenuRow(
            title: "Reduce Loud Sounds",
            value: canAdjust ? nil : Self.unavailable,
            isChecked: canAdjust && audio.adjustments.reducesLoudSounds,
            action: audio.toggleReduceLoudSounds
        )
        .disabled(!canAdjust)
        .focused($focusedRow, equals: .reduceLoudSounds)
        PlayerMenuDivider()
        PlayerMenuSectionHeader(title: "Audio Track")
        ForEach(audio.options) { option in
            PlayerMenuRow(title: option.title, value: option.detail, isChecked: option.id == audio.track?.id) {
                audio.select(option)
            }
            .focused($focusedRow, equals: .track(option.id))
        }
    }

    @ViewBuilder private var dialogueRows: some View {
        ForEach([AudioAdjustments.DialogueEnhancement.enhanceMore, .enhance, .off], id: \.self) { dialogue in
            PlayerMenuRow(title: dialogue.title, isChecked: dialogue == audio.adjustments.dialogue) {
                audio.setDialogue(dialogue)
            }
            .focused($focusedRow, equals: .dialogue(dialogue))
        }
    }
}
