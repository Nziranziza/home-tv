import Foundation

/// The viewer's audio adjustments, kept across titles.
@MainActor
final class AudioAdjustmentsStore {
    static let shared = AudioAdjustmentsStore()

    private let storageKey = "hometv.audioAdjustments.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var adjustments: AudioAdjustments {
        get {
            guard let data = defaults.data(forKey: storageKey),
                  let saved = try? JSONDecoder().decode(AudioAdjustments.self, from: data) else { return .init() }
            return saved
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: storageKey)
        }
    }
}
