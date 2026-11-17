import Foundation

extension PlayerRequest {
    /// The in-app request for an add-on stream. Only HTTP streams play in-app; magnets need an external app.
    init(
        stream: Stream,
        type: String,
        contentID: String,
        title: String,
        logoURL: URL?,
        startTime: TimeInterval,
        continuation: EpisodeContinuation? = nil
    ) throws {
        guard let url = stream.playableURL else { throw PlayerLaunchError.noPlayableURL }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw PlayerLaunchError.unsupportedInApp
        }
        self.init(
            url: url,
            type: type,
            title: title,
            logoURL: logoURL,
            headers: stream.behaviorHints?.proxyHeaders?.request ?? [:],
            startTime: startTime,
            item: PlaybackItem(contentID: contentID, showID: PlaybackSession.showID(fromEpisodeID: contentID)),
            subtitles: ExternalSubtitle.list(from: stream.subtitles),
            subtitleDelayKey: SubtitleDelayStore.streamKey(
                contentID: contentID,
                filename: stream.behaviorHints?.filename,
                url: url
            ),
            continuation: type == "series" ? continuation : nil
        )
    }
}
