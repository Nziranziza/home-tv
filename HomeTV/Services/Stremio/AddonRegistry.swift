import Foundation
import Observation

struct InstalledAddon: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var manifestURL: URL
    var manifest: StremioManifest
    var enabled: Bool

    var baseURL: URL {
        let s = manifestURL.absoluteString
        if s.hasSuffix("/manifest.json") {
            return URL(string: String(s.dropLast("/manifest.json".count))) ?? manifestURL
        }
        return manifestURL
    }
}

@Observable
@MainActor
final class AddonRegistry {
    static let shared = AddonRegistry()

    private(set) var addons: [InstalledAddon] = [] {
        didSet { enabledAddons = addons.filter(\.enabled) }
    }

    /// Cached enabled subset. `enabledAddons` is read on many hot paths (Watch Now row specs, Search
    /// catalogs, stream-picker load/status, detail load/related) — re-filtering `addons` on every access
    /// was wasteful, so it's maintained here and only recomputed when `addons` changes.
    private(set) var enabledAddons: [InstalledAddon] = []

    private let storageKey = "hometv.addons.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
        enabledAddons = addons.filter(\.enabled)   // didSet doesn't fire for assignments during init
        // Publish the current Trailerio base URL to the shared App Group so the Top Shelf extension can
        // resolve trailers. Done at launch too (not only on mutation) so an addon list already installed
        // before this feature shipped still reaches the extension without the user re-toggling anything.
        syncTopShelfState()
        if addons.isEmpty {
            Task { await seedDefaults() }
        }
    }

    func install(manifestURL: URL) async throws -> InstalledAddon {
        let manifest = try await StremioClient.shared.manifest(manifestURL: manifestURL)
        let addon = InstalledAddon(
            id: manifest.id,
            manifestURL: manifestURL,
            manifest: manifest,
            enabled: true
        )
        if let idx = addons.firstIndex(where: { $0.id == addon.id }) {
            addons[idx] = addon
        } else {
            addons.append(addon)
        }
        save()
        return addon
    }

    func remove(id: String) {
        addons.removeAll { $0.id == id }
        save()
    }

    func setEnabled(id: String, enabled: Bool) {
        guard let idx = addons.firstIndex(where: { $0.id == id }) else { return }
        addons[idx].enabled = enabled
        save()
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        addons.move(fromOffsets: fromOffsets, toOffset: toOffset)
        save()
    }

    private func seedDefaults() async {
        guard let url = URL(string: "https://v3-cinemeta.strem.io/manifest.json") else { return }
        do {
            _ = try await install(manifestURL: url)
        } catch {
            // Cinemeta unreachable on first launch — user can retry from Settings.
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([InstalledAddon].self, from: data) else {
            return
        }
        addons = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(addons) else { return }
        defaults.set(data, forKey: storageKey)
        syncTopShelfState()
    }

    /// Let the trailer feature mirror the Trailerio base URL to the shared App Group for the Top Shelf
    /// extension. Passing `enabledAddons` keeps the detection off the `AddonRegistry.shared` accessor,
    /// so this is safe to call from `init`; the Trailerio/App-Group specifics live in `TrailerSource`.
    private func syncTopShelfState() {
        TrailerSource.syncTopShelfState(with: enabledAddons)
    }
}
