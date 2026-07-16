import Foundation
import Observation

/// App-facing source of truth for Trakt. Mirrors the `@Observable @MainActor` singletons used
/// elsewhere (`AddonRegistry`, `WatchHistory`). Owns the OAuth token lifecycle (Keychain-backed),
/// the device-code sign-in flow, and in-memory caches of watched / watchlist / playback state that
/// the views read synchronously. Network plumbing is delegated to `TraktClient`.
///
/// Watched is a *manual* action (HomeTV plays via external players and never learns of completion),
/// so nothing is auto-marked. Playback progress is *read* from Trakt (scrobbled by other connected
/// players) to drive Continue Watching — we display it, we don't write it.
@Observable
@MainActor
final class TraktService {
    static let shared = TraktService()

    enum AuthState: Equatable {
        case signedOut
        case connecting                                              // requesting a device code
        case awaitingActivation(userCode: String, verificationURL: String)
        case signedIn(TraktUser)
    }

    private(set) var authState: AuthState = .signedOut
    private(set) var lastError: String?

    // Caches that drive the UI (populated by `refreshLibrary()`).
    private(set) var watchedMovieIDs: Set<String> = []     // imdb ids
    private(set) var watchedShowIDs: Set<String> = []      // imdb ids (show has any watched episode)
    private(set) var watchedEpisodeKeys: Set<String> = []  // "showImdb:season:episode"
    private(set) var watchlistIDs: Set<String> = []        // imdb ids (movies + shows)
    private(set) var playbackProgress: [String: Double] = [:]  // key → 0...1
    private(set) var watchlistItems: [MetaPreview] = []
    private(set) var continueWatchingItems: [MetaPreview] = []

    @ObservationIgnored private var tokens: TraktTokens?
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    private let tokenAccount = "tokens"
    private let usernameKey = "hometv.trakt.username"

    init() {
        guard TraktConfig.isConfigured,
              let str = Keychain.get(account: tokenAccount),
              let data = str.data(using: .utf8),
              let saved = try? JSONDecoder().decode(TraktTokens.self, from: data) else { return }
        tokens = saved
        // Provisional signed-in state so the UI doesn't flash "signed out" before `bootstrap()` runs.
        let name = UserDefaults.standard.string(forKey: usernameKey) ?? "Trakt account"
        authState = .signedIn(TraktUser(username: name, name: nil))
    }

    var isConfigured: Bool { TraktConfig.isConfigured }

    var isSignedIn: Bool {
        if case .signedIn = authState { return true }
        return false
    }

    /// True while the device-code flow is in progress (requesting a code or waiting for activation).
    var isAuthenticating: Bool {
        switch authState {
        case .connecting, .awaitingActivation: return true
        default: return false
        }
    }

    var username: String? {
        if case .signedIn(let user) = authState { return user.username }
        return nil
    }

    // MARK: - Launch

    /// Called at app launch. Validates the persisted token, refreshes the real account + caches.
    func bootstrap() async {
        guard TraktConfig.isConfigured, tokens != nil else { return }
        guard let token = await validAccessToken() else { return }
        if let user = try? await TraktClient.shared.user(token: token) {
            authState = .signedIn(user)
            UserDefaults.standard.set(user.username, forKey: usernameKey)
        }
        await refreshLibrary()
    }

    // MARK: - Device-code sign-in

    func startDeviceAuth() {
        guard TraktConfig.isConfigured else { return }
        pollTask?.cancel()
        lastError = nil
        authState = .connecting
        pollTask = Task { await self.runDeviceAuth() }
    }

    /// Stop an in-progress device-code poll (e.g. when leaving the Trakt settings screen) without
    /// disturbing an already-signed-in state.
    func cancelDeviceAuth() {
        pollTask?.cancel()
        pollTask = nil
        if !isSignedIn { authState = .signedOut }
    }

    private func runDeviceAuth() async {
        let code: TraktDeviceCode
        do {
            code = try await TraktClient.shared.deviceCode()
        } catch let error as TraktClientError {
            authState = .signedOut
            switch error {
            case .http(401), .http(403):
                lastError = "Trakt rejected the API key. Check the Client ID and Secret in TraktConfig."
            case .http(let status):
                lastError = "Trakt returned HTTP \(status). Please try again."
            default:
                lastError = "Couldn't reach Trakt. Check your connection and try again."
            }
            return
        } catch {
            authState = .signedOut
            lastError = "Couldn't reach Trakt. Check your connection and try again."
            return
        }

        authState = .awaitingActivation(userCode: code.userCode, verificationURL: code.verificationUrl)
        let deadline = Date().addingTimeInterval(TimeInterval(code.expiresIn))
        var interval = UInt64(max(code.interval, 1))

        while Date() < deadline {
            try? await Task.sleep(nanoseconds: interval * 1_000_000_000)
            if Task.isCancelled { return }

            do {
                let tokens = try await TraktClient.shared.deviceToken(deviceCode: code.deviceCode)
                persist(tokens)
                await finishSignIn()
                return
            } catch let error as TraktClientError {
                if error.isAuthorizationPending { continue }     // user hasn't entered the code yet
                if case .http(429) = error { interval += 1; continue }   // slow down
                // 404 invalid / 409 already used / 410 expired / 418 denied → stop.
                authState = .signedOut
                lastError = "Sign-in didn't complete. Please try again."
                return
            } catch {
                continue   // transient network blip — keep polling until the deadline
            }
        }

        if !Task.isCancelled {
            authState = .signedOut
            lastError = "The sign-in code expired. Please try again."
        }
    }

    private func finishSignIn() async {
        guard let token = tokens?.accessToken else { authState = .signedOut; return }
        var user = TraktUser(username: "Trakt account", name: nil)
        if let fetched = try? await TraktClient.shared.user(token: token) {
            user = fetched
            UserDefaults.standard.set(fetched.username, forKey: usernameKey)
        }
        authState = .signedIn(user)
        await refreshLibrary()
    }

    func signOut() {
        pollTask?.cancel()
        pollTask = nil
        persist(nil)
        UserDefaults.standard.removeObject(forKey: usernameKey)
        authState = .signedOut
        watchedMovieIDs = []
        watchedShowIDs = []
        watchedEpisodeKeys = []
        watchlistIDs = []
        playbackProgress = [:]
        watchlistItems = []
        continueWatchingItems = []
    }

    // MARK: - Library sync (reads)

    func refreshLibrary() async {
        guard let token = await validAccessToken() else { return }

        async let watchedMoviesReq = TraktClient.shared.watchedMovies(token: token)
        async let watchedShowsReq = TraktClient.shared.watchedShows(token: token)
        async let watchlistMoviesReq = TraktClient.shared.watchlistMovies(token: token)
        async let watchlistShowsReq = TraktClient.shared.watchlistShows(token: token)
        async let playbackMoviesReq = TraktClient.shared.playbackMovies(token: token)
        async let playbackEpisodesReq = TraktClient.shared.playbackEpisodes(token: token)

        let watchedMovies = (try? await watchedMoviesReq) ?? []
        let watchedShows = (try? await watchedShowsReq) ?? []
        let watchlistMov = (try? await watchlistMoviesReq) ?? []
        let watchlistSh = (try? await watchlistShowsReq) ?? []
        let playbackMov = (try? await playbackMoviesReq) ?? []
        let playbackEp = (try? await playbackEpisodesReq) ?? []

        // Watched. `/sync/watched/shows` reliably reports which shows have any watched episode
        // (show-level), but for many accounts it omits the per-season/episode breakdown entirely — so we
        // derive only show-level watched here. Per-episode watched state is loaded on demand from the
        // show progress endpoint when a show's detail opens (see `loadEpisodeProgress`), which is also
        // the only endpoint that returns each episode's `completed` flag reliably.
        var movieIDs = Set<String>()
        for m in watchedMovies { if let id = m.movie.ids.imdb { movieIDs.insert(id) } }

        var showIDs = Set<String>()
        for s in watchedShows {
            guard let showID = s.show.ids.imdb else { continue }
            showIDs.insert(showID)
        }

        // Watchlist
        var listIDs = Set<String>()
        var listItems: [MetaPreview] = []
        for m in watchlistMov where m.movie.ids.imdb != nil {
            let id = m.movie.ids.imdb!
            listIDs.insert(id)
            listItems.append(preview(imdb: id, type: "movie", name: m.movie.title ?? ""))
        }
        for s in watchlistSh where s.show.ids.imdb != nil {
            let id = s.show.ids.imdb!
            listIDs.insert(id)
            listItems.append(preview(imdb: id, type: "series", name: s.show.title ?? ""))
        }

        // Playback (continue watching). Movies and episodes come from separate endpoints; merge them
        // and order by `paused_at` descending so the most recently watched is first (newest activity),
        // interleaving movies and shows the way Trakt/Plex/Infuse "up next" do. Episodes also set a
        // show-level progress key so a series row in the (show-keyed) Continue Watching row has a value.
        var progress: [String: Double] = [:]
        let merged = (playbackMov + playbackEp)
            .sorted { ($0.pausedAt ?? "") > ($1.pausedAt ?? "") }   // ISO-8601 sorts correctly as text

        var continueItems: [MetaPreview] = []
        var seen = Set<String>()
        for item in merged {
            if item.type == "movie", let id = item.movie?.ids.imdb {
                progress[id] = item.progress / 100.0
                if seen.insert(id).inserted {
                    continueItems.append(preview(imdb: id, type: "movie", name: item.movie?.title ?? ""))
                }
            } else if let showID = item.show?.ids.imdb,
                      let season = item.episode?.season,
                      let number = item.episode?.number {
                progress["\(showID):\(season):\(number)"] = item.progress / 100.0
                if progress[showID] == nil { progress[showID] = item.progress / 100.0 }
                if seen.insert(showID).inserted {
                    continueItems.append(preview(imdb: showID, type: "series", name: item.show?.title ?? ""))
                }
            }
        }

        watchedMovieIDs = movieIDs
        watchedShowIDs = showIDs
        watchlistIDs = listIDs
        watchlistItems = listItems
        playbackProgress = progress
        continueWatchingItems = continueItems
        // `watchedEpisodeKeys` is a per-show cache this endpoint can't populate (no episode breakdown),
        // so it's left to `loadEpisodeProgress` — but prune keys for shows that just dropped out of
        // `watchedShowIDs` (un-watched entirely elsewhere) so the two caches stay aligned. Shows still
        // watched keep their keys and refresh the next time their detail screen opens.
        watchedEpisodeKeys = watchedEpisodeKeys.filter { key in
            guard let separator = key.firstIndex(of: ":") else { return false }
            return watchedShowIDs.contains(String(key[..<separator]))
        }
    }

    /// Load the per-episode watched state for a single show from the show progress endpoint and merge it
    /// into `watchedEpisodeKeys`. `/sync/watched/shows` doesn't return the season/episode breakdown, so
    /// this is the source of truth for episode checkmarks and the hero up-next. Called when a series
    /// detail opens (and when the app returns to a series detail after playing in an external player).
    /// Replaces only *this* show's keys, so it reflects un-watches made elsewhere without disturbing
    /// other shows' cached state.
    func loadEpisodeProgress(showIMDB: String) async {
        guard isSignedIn, let token = await validAccessToken(),
              let progress = try? await TraktClient.shared.showProgress(imdb: showIMDB, token: token)
        else { return }

        var keys = watchedEpisodeKeys.filter { !$0.hasPrefix("\(showIMDB):") }
        var hasWatchedEpisode = false
        for season in progress.seasons {
            for episode in season.episodes where episode.completed {
                keys.insert("\(showIMDB):\(season.number):\(episode.number)")
                hasWatchedEpisode = true
            }
        }
        watchedEpisodeKeys = keys
        // Keep the show-level watched set consistent with the episode keys we just inserted, rather than
        // the nullable `completed` aggregate — so a show still counts as watched even if Trakt reports a
        // null total while its episodes carry `completed: true`. An un-watch elsewhere clears it.
        if hasWatchedEpisode {
            watchedShowIDs.insert(showIMDB)
        } else {
            watchedShowIDs.remove(showIMDB)
        }
    }

    // MARK: - Queries (synchronous reads for views)

    func isWatched(type: String, imdb: String, season: Int? = nil, episode: Int? = nil) -> Bool {
        if let season, let episode {
            return watchedEpisodeKeys.contains("\(imdb):\(season):\(episode)")
        }
        return type == "series" ? watchedShowIDs.contains(imdb) : watchedMovieIDs.contains(imdb)
    }

    func isInWatchlist(imdb: String) -> Bool { watchlistIDs.contains(imdb) }

    /// Playback progress (0...1) for a movie/show imdb id, or an episode key "imdb:season:episode".
    func progress(forKey key: String) -> Double? { playbackProgress[key] }

    // MARK: - Actions (optimistic local update → API call → revert on failure)

    func toggleWatched(type: String, imdb: String) {
        guard isSignedIn else { return }
        let wasWatched = isWatched(type: type, imdb: imdb)
        setWatched(!wasWatched, type: type, imdb: imdb)
        Task {
            guard let token = await validAccessToken() else {
                setWatched(wasWatched, type: type, imdb: imdb); return
            }
            let body = syncBody(type: type, imdb: imdb)
            do {
                if wasWatched {
                    try await TraktClient.shared.removeFromHistory(body: body, token: token)
                } else {
                    try await TraktClient.shared.addToHistory(body: body, token: token)
                }
            } catch {
                setWatched(wasWatched, type: type, imdb: imdb)
                lastError = "Couldn't update your Trakt history."
            }
        }
    }

    func toggleWatchlist(type: String, imdb: String) {
        guard isSignedIn else { return }
        let wasInList = watchlistIDs.contains(imdb)
        if wasInList { watchlistIDs.remove(imdb) } else { watchlistIDs.insert(imdb) }
        Task {
            guard let token = await validAccessToken() else {
                revertWatchlist(toInList: wasInList, imdb: imdb); return
            }
            let body = syncBody(type: type, imdb: imdb)
            do {
                if wasInList {
                    try await TraktClient.shared.removeFromWatchlist(body: body, token: token)
                } else {
                    try await TraktClient.shared.addToWatchlist(body: body, token: token)
                }
            } catch {
                revertWatchlist(toInList: wasInList, imdb: imdb)
                lastError = "Couldn't update your Trakt watchlist."
            }
        }
    }

    /// Toggle watched for a single episode of a show — the episode the hero Play pill targets.
    /// Marking watched also clears any in-progress playback for that episode, so the up-next advances.
    func toggleEpisodeWatched(showIMDB: String, season: Int, episode: Int) {
        guard isSignedIn else { return }
        let key = "\(showIMDB):\(season):\(episode)"
        let wasWatched = watchedEpisodeKeys.contains(key)
        if wasWatched {
            watchedEpisodeKeys.remove(key)
        } else {
            watchedEpisodeKeys.insert(key)
            watchedShowIDs.insert(showIMDB)
            playbackProgress[key] = nil   // no longer in progress → up-next advances
        }
        Task {
            guard let token = await validAccessToken() else {
                if wasWatched { watchedEpisodeKeys.insert(key) } else { watchedEpisodeKeys.remove(key) }
                return
            }
            let body = episodeSyncBody(showIMDB: showIMDB, season: season, episode: episode)
            do {
                if wasWatched {
                    try await TraktClient.shared.removeFromHistory(body: body, token: token)
                } else {
                    try await TraktClient.shared.addToHistory(body: body, token: token)
                }
            } catch {
                if wasWatched { watchedEpisodeKeys.insert(key) } else { watchedEpisodeKeys.remove(key) }
                lastError = "Couldn't update your Trakt history."
            }
        }
    }

    // MARK: - Private helpers

    private func setWatched(_ watched: Bool, type: String, imdb: String) {
        if type == "series" {
            if watched {
                watchedShowIDs.insert(imdb)
            } else {
                watchedShowIDs.remove(imdb)
                watchedEpisodeKeys = watchedEpisodeKeys.filter { !$0.hasPrefix("\(imdb):") }
            }
        } else {
            if watched { watchedMovieIDs.insert(imdb) } else { watchedMovieIDs.remove(imdb) }
        }
    }

    private func revertWatchlist(toInList: Bool, imdb: String) {
        if toInList { watchlistIDs.insert(imdb) } else { watchlistIDs.remove(imdb) }
    }

    /// `/sync/*` body for a single episode: the show by IMDB id with the season/episode nested.
    private func episodeSyncBody(showIMDB: String, season: Int, episode: Int) -> Data {
        let object: [String: Any] = [
            "shows": [[
                "ids": ["imdb": showIMDB],
                "seasons": [["number": season, "episodes": [["number": episode]]]]
            ]]
        ]
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    /// `/sync/*` body identifying a single movie or show by IMDB id.
    private func syncBody(type: String, imdb: String) -> Data {
        let key = type == "series" ? "shows" : "movies"
        let object: [String: Any] = [key: [["ids": ["imdb": imdb]]]]
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    /// Returns a valid access token, refreshing first if the current one is near expiry. Signs out
    /// (and returns nil) if refresh fails — the refresh token was revoked/expired.
    private func validAccessToken() async -> String? {
        guard let current = tokens else { return nil }
        guard current.isExpired else { return current.accessToken }
        do {
            let refreshed = try await TraktClient.shared.refresh(refreshToken: current.refreshToken)
            persist(refreshed)
            return refreshed.accessToken
        } catch {
            signOut()
            return nil
        }
    }

    private func persist(_ newTokens: TraktTokens?) {
        tokens = newTokens
        if let newTokens,
           let data = try? JSONEncoder().encode(newTokens),
           let str = String(data: data, encoding: .utf8) {
            Keychain.set(str, account: tokenAccount)
        } else {
            Keychain.delete(account: tokenAccount)
        }
    }

    /// Build a `MetaPreview` for a Trakt item using its IMDB id. Artwork comes from Metahub (the same
    /// CDN the rest of the app uses for poster/background/logo), so these slot into existing rows.
    private func preview(imdb: String, type: String, name: String) -> MetaPreview {
        MetaPreview(
            id: imdb,
            type: type,
            name: name,
            poster: "https://images.metahub.space/poster/medium/\(imdb)/img",
            posterShape: nil,
            background: "https://images.metahub.space/background/medium/\(imdb)/img",
            logo: "https://images.metahub.space/logo/medium/\(imdb)/img",
            description: nil,
            releaseInfo: nil,
            imdbRating: nil,
            genres: nil
        )
    }
}
