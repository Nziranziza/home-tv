import Foundation

/// Asks every subtitle add-on for a title's files at once, alongside playback rather than ahead of it.
enum SubtitleAddonFetcher {
    /// The add-ons whose manifest serves subtitles for the query's type and id.
    static func sources(for query: SubtitleAddonQuery, in addons: [InstalledAddon]) -> [URL] {
        addons.filter { $0.manifest.provides("subtitles", type: query.type, id: query.id) }.map(\.baseURL)
    }

    /// Each add-on's files as its answer arrives. One that fails or times out in the client adds nothing.
    static func files(
        for query: SubtitleAddonQuery,
        in addons: [InstalledAddon],
        client: StremioClient = .shared
    ) -> AsyncStream<[ExternalSubtitle]> {
        let sources = sources(for: query, in: addons)
        return AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: [ExternalSubtitle].self) { group in
                    for source in sources {
                        group.addTask {
                            let response = try? await client.subtitles(baseURL: source, query: query)
                            return ExternalSubtitle.list(from: response?.subtitles)
                        }
                    }
                    for await files in group where !files.isEmpty { continuation.yield(files) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
