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

    /// The show a content id belongs to: `tt0903747` for `tt0903747:1:4`, `kitsu:1234` for `kitsu:1234:5`.
    nonisolated static func showKey(forContentID id: String) -> String {
        let parts = id.split(separator: ":")
        guard let first = parts.first else { return id }
        let isNamespace = parts.count > 1 && !first.contains(where: \.isNumber)
        return parts.prefix(isNamespace ? 2 : 1).joined(separator: ":")
    }

    func choice(forShow showID: String) -> SubtitleChoice? { choices[showID] }

    func record(_ choice: SubtitleChoice, forShow showID: String) {
        guard !showID.isEmpty else { return }
        choices[showID] = choice
        guard let data = try? JSONEncoder().encode(choices) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
