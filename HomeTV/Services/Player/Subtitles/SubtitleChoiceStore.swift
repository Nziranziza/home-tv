import Foundation

/// The last subtitle choice for each show (or movie), keyed by its id.
@MainActor
final class SubtitleChoiceStore {
    static let shared = SubtitleChoiceStore()

    private var choices: [String: SubtitleChoice] = [:]
    private let storageKey = "hometv.subtitleChoices.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([String: SubtitleChoice].self, from: data) else { return }
        choices = saved
    }

    func choice(forShow showID: String) -> SubtitleChoice? { choices[showID] }

    func record(_ choice: SubtitleChoice, forShow showID: String) {
        guard !showID.isEmpty else { return }
        choices[showID] = choice
        guard let data = try? JSONEncoder().encode(choices) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
