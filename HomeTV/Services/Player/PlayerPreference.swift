import Foundation
import Observation

@Observable
@MainActor
final class PlayerPreference {
    static let shared = PlayerPreference()

    private let storageKey = "hometv.defaultPlayer.v1"
    private let defaults: UserDefaults

    var defaultPlayer: ExternalPlayer {
        didSet {
            defaults.set(defaultPlayer.rawValue, forKey: storageKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.string(forKey: storageKey) ?? ExternalPlayer.infuse.rawValue
        self.defaultPlayer = ExternalPlayer(rawValue: raw) ?? .infuse
    }
}
