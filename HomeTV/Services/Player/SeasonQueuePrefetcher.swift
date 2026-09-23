import Foundation
import Observation

/// Resolves the other episodes' streams while the user is still choosing one, so the hand-off — which
/// needs the whole queue up front — costs nothing at launch.
@Observable
@MainActor
final class SeasonQueuePrefetcher {
    /// Streams resolved so far, keyed by Stremio episode id.
    private(set) var candidates: [String: [SeasonQueueBuilder.Candidate]] = [:]

    private var driver: Task<Void, Never>?
    private var startedKey: String?
    /// Requests still owed for each episode that was actually scheduled. An episode absent from this
    /// map was never asked about — the budget or a cancellation cut it — and waiting on it is futile.
    private var outstanding: [String: Int] = [:]
    /// Set when the driver stops, for whatever reason. Without it a wait on an episode that was never
    /// scheduled runs to its deadline and returns nothing better than it started with.
    private var finished = false
    /// Identifies the current run. Cancelling does not wait for the old driver, so without this a
    /// replaced driver could finish afterwards and end its replacement's wait early.
    private var run = 0

    /// In-flight add-on requests, kept small and paced: this is background work, and the add-on is
    /// also about to serve the stream the user actually chose.
    private static let concurrency = 3
    private static let batchPause: Duration = .milliseconds(250)

    /// How long `play` waits for the episodes ahead of the selection before giving up and queueing
    /// whatever has landed.
    static let coverageDeadline: Duration = .seconds(5)

    /// Ceiling on the requests one picker may issue, across every episode and add-on.
    private static let requestBudget = 250

    /// Begins resolving `episodeIDs`. Re-calling with the same episodes is a no-op.
    func start(type: String, episodeIDs: [String], addons: [InstalledAddon]) {
        let key = "\(type)|\(episodeIDs.joined(separator: ","))"
        guard startedKey != key else { return }
        cancel()
        startedKey = key
        candidates = [:]
        outstanding = [:]
        finished = false
        run += 1
        guard !episodeIDs.isEmpty, !addons.isEmpty else {
            finished = true
            return
        }
        let current = run
        driver = Task { [weak self] in
            await self?.resolve(type: type, episodeIDs: episodeIDs, addons: addons)
            guard let self, self.run == current else { return }
            self.finished = true
        }
    }

    /// Stops the outstanding requests, once the hand-off is built or the picker closes.
    func cancel() {
        driver?.cancel()
        driver = nil
        finished = true
    }

    /// True once every add-on scheduled for each of `episodeIDs` has answered, whatever it said. An
    /// episode that was never scheduled is never resolved — only `finished` ends a wait on one.
    func hasResolved(_ episodeIDs: [String]) -> Bool {
        episodeIDs.allSatisfy { outstanding[$0] == 0 }
    }

    /// Waits for those episodes to resolve, giving up after `deadline`. Whatever is still missing then
    /// simply shortens the queue.
    func awaitResolution(of episodeIDs: [String], within deadline: Duration) async {
        // A long show will not resolve in full before playback is expected, so aim for a useful depth.
        let wanted = Array(episodeIDs.prefix(Self.waitDepth))
        guard !wanted.isEmpty, driver != nil else { return }
        let expiry = ContinuousClock.now + deadline
        while !finished, !hasResolved(wanted), ContinuousClock.now < expiry {
            if Task.isCancelled { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private static let waitDepth = 30

    private func resolve(type: String, episodeIDs: [String], addons: [InstalledAddon]) async {
        // Episode-major, so the budget goes to the episodes nearest the selection.
        let jobs = episodeIDs
            .flatMap { id in addons.map { (episodeID: id, addon: $0) } }
            .prefix(Self.requestBudget)
        // Counted before any request goes out, so a wait can tell "still coming" from "never asked".
        for job in jobs { outstanding[job.episodeID, default: 0] += 1 }
        var index = 0
        while index < jobs.count {
            if Task.isCancelled { return }
            let slice = jobs[index..<min(index + Self.concurrency, jobs.count)]
            index += slice.count

            let batch = await withTaskGroup(
                of: (episodeID: String, candidates: [SeasonQueueBuilder.Candidate]).self
            ) { group in
                for job in slice {
                    let episodeID = job.episodeID
                    let baseURL = job.addon.baseURL
                    let addonID = job.addon.id
                    group.addTask {
                        do {
                            let response = try await StremioClient.shared.streams(
                                baseURL: baseURL,
                                type: type,
                                id: episodeID
                            )
                            let candidates = response.streams.map {
                                SeasonQueueBuilder.Candidate(stream: $0, addonID: addonID)
                            }
                            return (episodeID, candidates)
                        } catch {
                            // A failure shortens the queue and nothing more. Recorded as an empty
                            // result so "asked and got nothing" differs from "not asked yet".
                            return (episodeID, [])
                        }
                    }
                }
                var collected: [(episodeID: String, candidates: [SeasonQueueBuilder.Candidate])] = []
                for await result in group { collected.append(result) }
                return collected
            }

            if Task.isCancelled { return }
            for result in batch {
                candidates[result.episodeID, default: []].append(contentsOf: result.candidates)
                outstanding[result.episodeID] = max((outstanding[result.episodeID] ?? 1) - 1, 0)
            }
            if index < jobs.count { try? await Task.sleep(for: Self.batchPause) }
        }
    }
}
