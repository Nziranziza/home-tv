import Foundation

/// Which store answers for the user's library: Trakt when connected, this device otherwise. Keeping the
/// choice here means the views never ask whether the user is signed in.
@MainActor
enum UserLibrary {
    private static var trakt: TraktService { .shared }
    private static var local: LocalLibrary { .shared }

    // MARK: - Watched

    /// A movie or a whole show. Episodes go through the `episode` calls below — the two are kept
    /// apart on purpose: a single call taking optional season/episode numbers silently degrades to
    /// the show when an episode turns out to be unnumbered, which marks a whole series watched.
    static func isWatched(type: String, id: String) -> Bool {
        if trakt.isSignedIn { return trakt.isWatched(type: type, imdb: id) }
        guard let key = LocalLibrary.id(show: id) else { return false }
        return local.isWatched(key)
    }

    static func toggleWatched(type: String, id: String) {
        if trakt.isSignedIn {
            trakt.toggleWatched(type: type, imdb: id)
            return
        }
        guard let key = LocalLibrary.id(show: id) else { return }
        local.toggleWatched(id: key)
    }

    /// One episode. Unnumbered videos report unwatched and cannot be marked; hide the control for them.
    static func isEpisodeWatched(type: String, showID: String, season: Int?, episode: Int?) -> Bool {
        guard let season, let episode else { return false }
        if trakt.isSignedIn {
            return trakt.isWatched(type: type, imdb: showID, season: season, episode: episode)
        }
        guard let key = LocalLibrary.id(show: showID, season: season, episode: episode) else { return false }
        return local.isWatched(key)
    }

    static func toggleEpisodeWatched(showID: String, season: Int?, episode: Int?) {
        guard let season, let episode else { return }
        if trakt.isSignedIn {
            trakt.toggleEpisodeWatched(showIMDB: showID, season: season, episode: episode)
            return
        }
        guard let key = LocalLibrary.id(show: showID, season: season, episode: episode) else { return }
        local.toggleWatched(id: key)
    }

    /// Something a player reported having played. Only ever sets, so revisiting a season cannot
    /// un-watch it. Recorded locally even with Trakt connected, so it survives signing out.
    static func markEpisodeWatched(showID: String, season: Int, episode: Int) {
        guard let key = LocalLibrary.id(show: showID, season: season, episode: episode) else { return }
        local.setWatched(true, id: key)
        guard trakt.isSignedIn,
              !trakt.isWatched(type: "series", imdb: showID, season: season, episode: episode) else { return }
        trakt.toggleEpisodeWatched(showIMDB: showID, season: season, episode: episode)
    }

    // MARK: - Progress

    /// Playback progress (0...1) for a content id — `tt0903747` or `tt0903747:1:4`.
    static func progress(forKey key: String) -> Double? {
        trakt.isSignedIn ? trakt.progress(forKey: key) : local.progress(forKey: key)
    }

    /// Where a player left off. Always local: there is no client-side Trakt write for playback progress.
    static func recordProgress(_ fraction: Double, id: String) {
        local.setProgress(fraction, id: id)
    }

    // MARK: - Watchlist

    static var watchlistItems: [MetaPreview] {
        trakt.isSignedIn ? trakt.watchlistItems : local.watchlist
    }

    static func isInWatchlist(id: String) -> Bool {
        trakt.isSignedIn ? trakt.isInWatchlist(imdb: id) : local.isInWatchlist(id)
    }

    static func toggleWatchlist(_ preview: MetaPreview) {
        if trakt.isSignedIn {
            trakt.toggleWatchlist(type: preview.type, imdb: preview.id)
        } else {
            local.toggleWatchlist(preview)
        }
    }
}
