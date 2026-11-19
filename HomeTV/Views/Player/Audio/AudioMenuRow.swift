/// An Audio menu row's focus identity.
enum AudioMenuRow: Hashable {
    case enhanceDialogue
    case reduceLoudSounds
    case track(Int32)
    case dialogue(AudioAdjustments.DialogueEnhancement)
}
