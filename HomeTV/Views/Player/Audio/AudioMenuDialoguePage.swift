import SwiftUI

/// Enhance Dialogue's levels, strongest first.
struct AudioMenuDialoguePage: View {
    let audio: PlayerAudio
    let focus: FocusState<AudioMenuRow?>.Binding

    static let levels: [AudioAdjustments.DialogueEnhancement] = [.enhanceMore, .enhance, .off]
    static var rowsHeight: CGFloat { CGFloat(levels.count) * PlayerMenuRow.height }

    var body: some View {
        ForEach(Self.levels, id: \.self) { dialogue in
            PlayerMenuRow(title: dialogue.title, isChecked: dialogue == audio.adjustments.dialogue) {
                audio.setDialogue(dialogue)
            }
            .focused(focus, equals: .dialogue(dialogue))
        }
    }
}
