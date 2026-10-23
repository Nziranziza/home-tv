/// Records where a player left a title: the resume point, and the watched mark once it's played through.
/// Shared by the Infuse callback and the in-app player, so both reconcile the library the same way.
@MainActor
enum PlaybackProgress {
    /// - Parameters:
    ///   - runtimeIsOwn: whether `runtime` is this item's own. A borrowed one is too rough to call the
    ///     item finished.
    ///   - isRestart: the user went back to the start on purpose, which is a play, not a stray open.
    static func record(
        position: Int,
        runtime: Int,
        item: PlaybackItem,
        runtimeIsOwn: Bool = true,
        isRestart: Bool = false
    ) {
        guard runtime > 0 else { return }
        let fraction = Double(position) / Double(runtime)
        UserLibrary.recordProgress(fraction, seconds: position, isRestart: isRestart, id: item.contentID)
        // Played to the end: finished, not just a resume point.
        if fraction > LocalLibrary.resumeRange.upperBound, runtimeIsOwn,
           let season = item.season, let episode = item.episode {
            UserLibrary.markEpisodeWatched(showID: item.showID, season: season, episode: episode)
        }
        // Continue Watching cards are keyed by the show, so the resume point is recorded there too.
        if item.contentID != item.showID, !item.showID.isEmpty {
            UserLibrary.recordProgress(fraction, seconds: position, isRestart: isRestart, id: item.showID)
        }
    }
}
