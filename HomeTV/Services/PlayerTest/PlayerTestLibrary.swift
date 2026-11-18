import Foundation
import Observation

/// Loads the sample catalog, lists files copied to Caches, and plays a sample in HomeTV or Infuse.
@Observable
@MainActor
final class PlayerTestLibrary {
    enum LoadState {
        case loading
        case loaded(PlayerTestIndex)
        case failed(String)
    }

    private(set) var state = LoadState.loading
    private(set) var localFiles: [PlayerTestItem] = []
    private(set) var lastPlayed: PlayerTestReplay?
    /// Set when Infuse refuses a launch; shown as an alert.
    var launchError: String?
    /// Checked once: `canOpenURL` per row would be wasteful.
    let isInfuseInstalled = ExternalPlayer.infuse.isInstalled

    private static let replayKey = "playerTest.lastPlayed"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lastPlayed = defaults.data(forKey: Self.replayKey)
            .flatMap { try? JSONDecoder().decode(PlayerTestReplay.self, from: $0) }
    }

    var index: PlayerTestIndex? {
        if case .loaded(let index) = state { index } else { nil }
    }

    /// Loads once; a retry after a failure loads again.
    func load() async {
        guard index == nil, let url = PlayerTestCatalog.url else { return }
        state = .loading
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                state = .failed("The catalog request returned HTTP \(http.statusCode).")
                return
            }
            state = .loaded(try await Self.buildIndex(data))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Off the main actor: the catalog is about 1.7 MB and every entry is indexed for search.
    nonisolated private static func buildIndex(_ data: Data) async throws -> PlayerTestIndex {
        PlayerTestIndex(try PlayerTestCatalog.decode(data))
    }

    func scope(for route: PlayerTestRoute) -> PlayerTestScope? {
        guard route == .local else { return index?.scope(for: route) }
        return PlayerTestScope(
            title: "On This Apple TV",
            summary: "Files in HomeTV's Caches folder, for clips that are only on Google Drive or Mega.",
            symbol: "internaldrive",
            entries: localFiles.enumerated().map { offset, item in
                PlayerTestEntry(id: offset, item: item, sectionID: "local", sectionTitle: "On This Apple TV",
                                groupTitle: "Caches", expect: .play)
            },
            isLocal: true
        )
    }

    /// Files in Caches, where `devicectl device copy to` puts them.
    func refreshLocalFiles() {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: .cachesDirectory,
            includingPropertiesForKeys: keys,
            options: .skipsHiddenFiles
        )) ?? []
        localFiles = urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { return nil }
            return PlayerTestItem(
                title: url.lastPathComponent,
                url: url,
                container: url.pathExtension.lowercased(),
                size: values?.fileSize.map(Int64.init)
            )
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func play(_ item: PlayerTestItem, expect: PlayerTestExpectation, in player: ExternalPlayer) async {
        remember(PlayerTestReplay(item: item, expect: expect, player: player))
        let url = Self.resolved(item.url)
        if player == .infuse {
            // A leftover launch from a real title must not pick up this callback.
            PlaybackReturnCoordinator.shared.willLaunch(nil)
            do {
                try await PlayerLauncher.open(mediaURL: url, using: .infuse, filename: item.filename)
            } catch {
                launchError = error.localizedDescription
            }
        } else {
            // No `item`, so no progress is saved.
            PlayerPresenter.shared.present(PlayerRequest(url: url, title: item.title, headers: item.headers ?? [:]))
        }
    }

    private func remember(_ replay: PlayerTestReplay) {
        lastPlayed = replay
        defaults.set(try? JSONEncoder().encode(replay), forKey: Self.replayKey)
    }

    /// The app container moves between installs, so a saved Caches file is found again by name.
    static func resolved(_ url: URL) -> URL {
        url.isFileURL ? URL.cachesDirectory.appending(path: url.lastPathComponent) : url
    }
}
