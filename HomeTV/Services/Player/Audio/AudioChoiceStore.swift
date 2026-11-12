import Foundation

/// The last audio choice for each show (or movie), keyed by `SubtitleChoiceStore.showKey`.
@MainActor
final class AudioChoiceStore {
    static let shared = AudioChoiceStore()

    private var choices: [String: AudioChoice] = [:]
    private let storageKey = "hometv.audioChoices.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([String: AudioChoice].self, from: data) else { return }
        choices = saved
    }

    func choice(forShow showID: String) -> AudioChoice? { choices[showID] }

    func record(_ choice: AudioChoice, forShow showID: String) {
        guard !showID.isEmpty else { return }
        choices[showID] = choice
        guard let data = try? JSONEncoder().encode(choices) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
