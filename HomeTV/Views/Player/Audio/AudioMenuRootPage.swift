import SwiftUI

/// The Audio menu's top level: Enhance Dialogue and Reduce Loud Sounds, then the stream's audio tracks.
struct AudioMenuRootPage: View {
    let audio: PlayerAudio
    let focus: FocusState<AudioMenuRow?>.Binding
    let onOpen: (AudioMenuPage) -> Void

    private static let unavailable = "Not available for this audio"

    static func rowsHeight(_ audio: PlayerAudio) -> CGFloat {
        let tracks = audio.options.reduce(0) { height, option in
            height + (option.detail == nil ? PlayerMenuRow.height : PlayerMenuRow.heightWithValue)
        }
        let reduceLoudSounds = audio.canAdjust ? PlayerMenuRow.height : PlayerMenuRow.heightWithValue
        return PlayerMenuRow.heightWithValue + reduceLoudSounds + PlayerMenuDivider.height
            + PlayerMenuSectionHeader.height + tracks
    }

    var body: some View {
        let canAdjust = audio.canAdjust
        PlayerMenuRow(
            title: "Enhance Dialogue",
            value: canAdjust ? audio.adjustments.dialogue.title : Self.unavailable,
            accessory: canAdjust ? .chevron : .none
        ) {
            onOpen(.enhanceDialogue)
        }
        .disabled(!canAdjust)
        .focused(focus, equals: .enhanceDialogue)
        PlayerMenuRow(
            title: "Reduce Loud Sounds",
            value: canAdjust ? nil : Self.unavailable,
            isChecked: canAdjust && audio.adjustments.reducesLoudSounds,
            action: audio.toggleReduceLoudSounds
        )
        .disabled(!canAdjust)
        .focused(focus, equals: .reduceLoudSounds)
        PlayerMenuDivider()
        PlayerMenuSectionHeader(title: "Audio Track")
        ForEach(audio.options) { option in
            PlayerMenuRow(title: option.title, value: option.detail, isChecked: option.id == audio.track?.id) {
                audio.select(option)
            }
            .focused(focus, equals: .track(option.id))
        }
    }
}
