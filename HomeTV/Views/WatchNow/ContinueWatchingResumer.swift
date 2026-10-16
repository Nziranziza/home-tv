import Foundation
import Observation

/// Continue Watching's one-click resume: plays a card's title with the stream it was last launched with,
/// at the saved position, or hands back a picker request when that stream can't be found again.
@Observable
@MainActor
final class ContinueWatchingResumer {
    /// The card resolving right now. Further selections are ignored until it settles.
    private(set) var resumingID: String?

    enum Outcome {
        case launched
        /// No remembered stream, or it is gone: let the user choose.
        case chooseStream(StreamRequest)
        case cancelled
    }

    func resume(_ item: WatchHistoryItem) async -> Outcome {
        guard resumingID == nil else { return .cancelled }
        resumingID = item.id
        defer { resumingID = nil }

        // The same episode the detail screen's Resume and the hero's Play target.
        guard let request = await MetaDetailModel.heroPlaybackRequest(for: item.preview) else { return .cancelled }
        let titleID = PlaybackSession.showID(fromEpisodeID: request.contentID)
        guard let choice = StreamChoiceStore.shared.choice(forTitle: titleID),
              let addon = AddonRegistry.shared.enabledAddons.first(where: { $0.id == choice.addonID })
        else { return .chooseStream(request) }

        // Meta loads alongside the stream lookup; `launch` waits for it only up to its own deadline.
        let session = PlaybackSession(type: request.type, contentID: request.contentID, title: request.title)
        let preparation = Task { await session.prepare() }
        defer {
            preparation.cancel()
            session.cancel()
        }

        let candidates: [SeasonQueueBuilder.Candidate]
        do {
            candidates = try await StremioClient.shared
                .streams(baseURL: addon.baseURL, type: request.type, id: request.contentID)
                .streams
                .map { SeasonQueueBuilder.Candidate(stream: $0, addonID: addon.id) }
        } catch {
            candidates = []
        }
        guard !Task.isCancelled else { return .cancelled }
        guard let stream = choice.match(for: request.contentID, among: candidates) else {
            return .chooseStream(request)
        }

        do {
            try await session.launch(stream, addonID: addon.id)
            return .launched
        } catch {
            if Task.isCancelled { return .cancelled }
            // Never fail silently: the picker offers the other streams.
            return .chooseStream(request)
        }
    }
}
