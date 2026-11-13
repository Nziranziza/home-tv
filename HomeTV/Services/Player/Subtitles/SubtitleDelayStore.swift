import Foundation

/// The subtitle timing set for each stream. Timing belongs to a file, not a show: another release of the
/// same episode is cut differently.
@MainActor
final class SubtitleDelayStore {
    static let shared = SubtitleDelayStore()

    private var delays: [String: TimeInterval] = [:]
    private let storageKey = "hometv.subtitleDelays.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([String: TimeInterval].self, from: data) else { return }
        delays = saved
    }

    /// A stream's key: its title, then the file's add-on name, which outlives the URL's tokens.
    nonisolated static func streamKey(contentID: String, filename: String?, url: URL) -> String {
        "\(contentID)|\(filename ?? url.absoluteString)"
    }

    func delay(forStream key: String) -> TimeInterval { delays[key] ?? 0 }

    func record(_ delay: TimeInterval, forStream key: String) {
        guard !key.isEmpty else { return }
        delays[key] = delay == 0 ? nil : delay
        guard let data = try? JSONEncoder().encode(delays) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
