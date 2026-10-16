import Foundation
import Observation

/// The last stream chosen for each title, keyed by movie id or show id, so Continue Watching can resume
/// without asking again.
@Observable
@MainActor
final class StreamChoiceStore {
    static let shared = StreamChoiceStore()

    private var choices: [String: StreamChoice] = [:]
    private let storageKey = "hometv.streamChoices.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([String: StreamChoice].self, from: data) else { return }
        choices = saved
    }

    func choice(forTitle titleID: String) -> StreamChoice? { choices[titleID] }

    func record(_ choice: StreamChoice, forTitle titleID: String) {
        guard !titleID.isEmpty else { return }
        choices[titleID] = choice
        guard let data = try? JSONEncoder().encode(choices) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
