import Foundation
import Observation

@Observable
@MainActor
final class PlayerPreference {
    static let shared = PlayerPreference()

    private let storageKey = "hometv.defaultPlayer.v1"
    private let skipsSegmentsKey = "hometv.skipSegments.v1"
    private let defaults: UserDefaults

    var defaultPlayer: ExternalPlayer {
        didSet {
            defaults.set(defaultPlayer.rawValue, forKey: storageKey)
        }
    }

    /// Skip Intros & Credits: the in-app player offers Skip Intro, Skip Recap and Skip Credits.
    var skipsSegments: Bool {
        didSet {
            defaults.set(skipsSegments, forKey: skipsSegmentsKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.skipsSegments = defaults.object(forKey: skipsSegmentsKey) as? Bool ?? true
        let raw = defaults.string(forKey: storageKey) ?? ExternalPlayer.builtIn.rawValue
        self.defaultPlayer = ExternalPlayer(rawValue: raw) ?? .builtIn
    }
}
