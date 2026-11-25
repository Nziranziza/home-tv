---
title: Playback architecture
description: How a chosen stream reaches a player, how the in-app engines work, and how to add an engine or an external player.
---

This page covers everything between selecting a stream and the library recording where you got to. For how the
stream picker is reached, see [From Watch Now to playback](/developers/architecture/#from-watch-now-to-playback).
All the code is in `HomeTV/Services/Player/`, except `PlayerModel` and the player's views in `HomeTV/Views/Player/`.

## Overview

```text
StreamPickerView or ContinueWatchingResumer
  │
  ▼
PlaybackSession.launch(stream)
  │  Loads the title's meta for the runtime, the episode list and the show name
  │  Records the stream in StreamChoiceStore
  │
  ├─ HomeTV ──► PlayerPresenter ──► PlayerScreen ──► PlayerModel ──► PlaybackEngine
  │                                                                     ├─ KSPlaybackEngine (Apple TV)
  │                                                                     └─ AVPlaybackEngine (simulator)
  │
  └─ Infuse, VLC, System Default ──► PlayerLauncher ──► UIApplication.open
                                       Infuse calls back ──► PlaybackReturnCoordinator
```

Both paths end in `PlaybackProgress.record`, which saves the resume point and marks a finished episode watched.

## The in-app engine

### `PlaybackEngine`

`PlaybackEngine` is the protocol between `PlayerModel` and a video decoder. Views never see the engine: they read
`PlayerModel`, which forwards the engine's state and calls it. `PlayerModel`'s `init` takes an `engine:` argument,
so tests pass `FakePlaybackEngine` from `HomeTVTests/` instead.

| Member | Contract |
| --- | --- |
| `videoView` | The `UIView` the engine renders into. The same view for the engine's whole life. |
| `state` | `idle`, `loading`, `buffering`, `playing`, `paused`, `ended` or `failed`. `loading` covers everything before the first frame. |
| `currentTime`, `duration` | In seconds. `duration` is 0 until it's known. |
| `isSeeking` | True from `seek(to:isAccurate:)` until the engine lands. |
| `videoFormat` | Size, dynamic range and frame rate, once `onTracksReady` has fired. Drives the quality badges and the preview's aspect ratio. |
| `prepare(url:headers:startTime:)` | Opens and buffers the stream without playing it or switching the TV's mode. Called while a stream picker row has focus. |
| `load(url:headers:startTime:)` | Starts playback. When the same stream was prepared, plays from that buffer instead of opening it again. |
| `play()`, `pause()`, `seek(to:isAccurate:)` | `isAccurate` lands on the exact second; otherwise a nearby keyframe is fine. |
| `tracks(of:)`, `select(_:)`, `selectSubtitle(_:)` | Audio, video and subtitle tracks as `PlaybackTrack`. `selectSubtitle(nil)` turns subtitles off. |
| `externalSubtitles` | Add-on subtitle files, listed by `tracks(of: .subtitle)` after the stream's own. Files are appended while playing, so existing indexes never move. |
| `subtitleDelay` | Seconds; positive shows subtitles later. |
| `audioPicker` | Picks the audio track the stream opens with. Can be called off the main actor. |
| `audioAdjustments`, `canAdjustAudio` | Enhance Dialogue and Reduce Loud Sounds, applied live; `canAdjustAudio` is false when the playing audio can't take them. |
| `onTracksReady` | Called each time the tracks become known, including after a decoder restart. `PlayerModel` picks the audio and subtitles here. |
| `onFinish` | Called once, when playback ends, with the error if it failed. |
| `loadChapters()` | The file's chapters, for Skip Intro and Skip Credits. Empty when it has none. |
| `stop()` | Releases the decoder. The engine isn't used again. |

An engine must also be:

- **`@MainActor`**, like the protocol.
- **`@Observable`**. `PlayerScreen` watches `model.state`, which reads `engine.state`; an engine that isn't
  observable never moves the player off its loading screen.

Errors are shown as *This stream couldn't be played.* An engine that throws `PlaybackError.unsupportedFormat` gets
*The simulator can't play this stream's format* instead, so only the simulator stub throws it.

### Choosing the engine

`PlaybackEngines.make()` returns the engine for the build:

```swift
#if canImport(KSPlayer)
KSPlaybackEngine()
#else
AVPlaybackEngine()
#endif
```

`KSPlayer` can be imported only in device builds, because the frameworks have no simulator slice. See
[Vendored frameworks](#vendored-frameworks).

### `KSPlaybackEngine`

The Apple TV engine wraps [KSPlayer](https://github.com/kingslay/KSPlayer), which has two players: `KSAVPlayer`, built
on AVPlayer, and `KSMEPlayer`, built on FFmpeg. KSPlayer's types stay inside the engine files
(`KSPlaybackEngine.swift`, `KSPlaybackOptions.swift`, `AudioAdjustmentTap.swift`).

#### Routing by container

`PlaybackRoute.forURL` picks the decoder a stream starts on, from the URL's file extension:

| Extension | Route | Player |
| --- | --- | --- |
| `mkv`, `avi`, `webm` | `.ffmpeg` | `KSMEPlayer` |
| Anything else, including none | `.native` | `KSAVPlayer` |

The native route comes first because AVPlayer keeps Dolby Vision and Atmos. Containers AVPlayer can't open go
straight to FFmpeg, so they don't fail on AVPlayer first.

#### The FFmpeg fallback

KSPlayer's own native-to-FFmpeg fallback doesn't fire, so each start runs on one decoder and the engine retries
itself. When the layer reports a failure in `player(layer:finish:)`:

- A **native** start restarts on FFmpeg, at the current position or the requested start time.
- An **FFmpeg** start on a resolved URL restarts on FFmpeg with the original URL, in case the resolved link expired.
- Any other failure goes to `onFinish`.

Before an FFmpeg start, `StreamRedirect.finalURL` sends a `HEAD` request and opens the URL the redirects end at.
FFmpeg follows a debrid link's redirects again on every range request, at a second or more each, so this saves time
on every seek. The debug variable `PLAYER_NO_RESOLVE=1` turns it off.

#### Starting at a position

`KSAVPlayer` ignores KSPlayer's `startPlayTime`. For a native start after 0, the engine holds autoplay, hides the
video until the layer is ready, seeks there accurately and then plays, so the first frame you see is at the resume
point. `KSMEPlayer` honours `startPlayTime`.

#### Prepare, Select and the TV's mode

With Match Content on, a stream's first frame switches the TV's frame rate and dynamic range, and the screen goes
black while it changes. A prepared stream must not do that before Select:

- `KSPlaybackOptions` holds back the display criteria while `defersDisplayCriteria` is set, and applies them in
  `applyDeferredDisplayCriteria()` when `load` runs.
- `DisplayModeSwitch` watches the switch starting and ending. Playback waits while it's in progress, and the engine
  reports `loading` meanwhile. `stop()` sets the TV back to its default mode.

`KSPlaybackOptions` also sets a 1-second start buffer and a 60-second buffer ceiling. `PLAYER_STOCK_OPTIONS=1` uses
KSPlayer's defaults instead, for comparison.

### `AVPlaybackEngine`, the simulator stub

The simulator engine plays through a plain `AVPlayer`, so the player's UI builds and runs without KSPlayer. It
ignores request headers, can't show add-on subtitle files, and plays MP4 and HLS only. It fails MKV, HEVC and Dolby
Vision with `PlaybackError.unsupportedFormat`, including video the simulator would otherwise play as a black screen.
Most add-on streams fail in the simulator by design.

### Prewarming

While a stream picker row has focus for 300 ms, `StreamPickerView` calls `PlaybackSession.prewarm`, which builds the
same `PlayerRequest` Select would and hands it to `PlayerPrewarmer`. The prewarmer creates a `PlayerModel` and calls
`prepare()`, which calls the engine's `prepare`. It holds one prepared play at a time and closes it when focus moves.

On Select, `PlayerScreen` asks `PlayerPrewarmer.take(for:)` for a model whose request `isSamePlay(as:)` the new one,
and starts it; otherwise it creates a fresh `PlayerModel`. Up Next prewarms the next episode the same way.
`PLAYER_NO_PREWARM=1` turns prewarming off.

## Vendored frameworks

KSPlayer and FFmpeg aren't Swift packages in this project. `scripts/fetch-player-frameworks.sh` downloads them into
`Vendor/PlayerFrameworks`, which is gitignored.

### Why not Swift Package Manager

- **No simulator slice.** KSPlayer's free GPL build ships an Apple TV slice only. A package is linked for every SDK,
  so a simulator build fails. A vendored framework can be linked for device builds alone.
- **Clone size.** Resolving the packages clones the KSPlayer and FFmpegKit repositories, which takes hours. The script
  does a shallow, sparse fetch of just the `tvos-arm64` framework folders.

### Pinned versions

The versions are at the top of the script:

| Variable | Pins |
| --- | --- |
| `KSPLAYER_REVISION` | The KSPlayer commit |
| `FFMPEGKIT_TAG`, `FFMPEGKIT_REVISION` | The FFmpegKit release and its commit. The commit is the pin, since a tag can move. |
| `FFMPEG_FRAMEWORKS` | The dynamic frameworks KSPlayer loads at runtime: the `Libav*` libraries, `Libswresample`, `Libswscale`, `libfribidi`, `libplacebo` and `libzvbi` |

The script copies everything into a staging folder next to the destination, writes `VERSION` last, then swaps the
folders, so a failed run leaves the installed set as it was.

### How the build uses them

In `project.yml`, the `HomeTV` target:

- adds `Vendor/PlayerFrameworks` to `FRAMEWORK_SEARCH_PATHS[sdk=appletvos*]` and links `-framework KSPlayer` in
  `OTHER_LDFLAGS[sdk=appletvos*]`. Simulator builds don't see the frameworks, so `canImport(KSPlayer)` is false
  there.
- runs an **Embed player frameworks** script after compiling. On device builds it copies every framework in
  `Vendor/PlayerFrameworks` into the app and signs it, since KSPlayer loads the FFmpeg ones at runtime. Without
  `VERSION`, it stops the build with *Player frameworks missing*.

`HomeTVTests` has the same search path, so `@testable import HomeTV` builds for a device.

### Updating KSPlayer or FFmpeg

1. Change the revision variables in `scripts/fetch-player-frameworks.sh`.
2. If the new FFmpegKit loads a different set of dynamic frameworks, update `FFMPEG_FRAMEWORKS`.
3. Run the script, build for a device and play an MKV, an MP4 and an HLS stream.
4. Check that the new KSPlayer revision is still the free GPL build. The paid build has a different license.

## Adding an engine

1. Create a `@MainActor @Observable final class` that conforms to `PlaybackEngine`, in
   `HomeTV/Services/Player/Engine/`. If it wraps a framework, keep that framework's types inside the engine's files.
2. Report `loading` until the first frame, then follow the player with `buffering`, `playing` and `paused`. Call
   `onTracksReady` each time the tracks are known, and `onFinish` exactly once.
3. Make `prepare` buffer without playing and without changing the TV's mode, and make `load` reuse that buffer for
   the same URL, headers and start time. An engine that can't do this can open the stream in `load` instead; the
   player still works, it just starts slower.
4. Return it from `PlaybackEngines.make()`. If it depends on a framework that isn't in every build, put it behind
   `#if canImport(...)` like `KSPlaybackEngine`, and add the framework to `project.yml` for the SDKs that have it.
5. Run `xcodegen generate`, then the player's model tests (`InAppPlayerTests`, `PlayerPrewarmTests`,
   `PlayerProgressTests` and the other `Player*Tests`). They run against `FakePlaybackEngine`, so update it if you
   add to the protocol.
6. Test it on an Apple TV. See [Testing on the Apple TV](#testing-on-the-apple-tv).

## External players

### `ExternalPlayer`

`ExternalPlayer` lists the players you can pick in **Settings → Default Player**: `builtIn` (HomeTV), `infuse`,
`vlc` and `system`. `PlayerPreference.defaultPlayer` stores the choice under `hometv.defaultPlayer.v1`.

`isInstalled` calls `canOpenURL` on the player's `probeURL`. The Settings picker disables a player that isn't
installed. `canOpenURL` only answers for schemes listed in `LSApplicationQueriesSchemes` in `project.yml`, so a
player missing from that list always shows as **Not Installed**.

### `PlayerLauncher`

`PlayerLauncher.launchURL(for:player:title:filename:startPosition:token:)` builds the URL each player opens:

| Player | URL | Start position | Calls back |
| --- | --- | --- | --- |
| Infuse | `infuse://x-callback-url/play?url=…&position=…&filename=…&x-success=…&x-error=…` | Yes | Yes |
| VLC | `vlc-x-callback://x-callback-url/stream?url=…` | No | No |
| System Default | The media URL itself | No | No |
| HomeTV | None; it plays through `PlayerPresenter` | | |

`open` checks `canOpenURL`, then calls `UIApplication.open`. It throws `PlayerLaunchError.playerUnavailable` when
the player isn't installed and `failedToOpen` when tvOS refuses the URL. The stream picker shows the error.

Some details of the Infuse URL matter:

- **Encoding.** Every value is percent-encoded to the RFC 3986 unreserved set. `URLComponents.queryItems` leaves
  `&`, `=`, `+` and `?` unencoded inside a value, which breaks the query of a real add-on URL, and Infuse refuses
  the whole launch without saying why.
- **`filename` identifies the title.** Infuse's scheme has no ID, season or episode parameter, so Infuse matches
  the title, fetches its artwork and scrobbles to Trakt from the filename. `PlayerFilename` builds it in the style
  Infuse parses: `Severance S01E04 The You You Are.mkv` for an episode and `Dune (2021).mkv` for a movie. It must be
  flat and start with the show name; a folder form such as `Show/S01E04.mkv` breaks matching.
- **Callbacks.** `x-success` is `hometv://playback-done-<token>` and `x-error` is
  `hometv://playback-error-<token>`. See [Returning from Infuse](#returning-from-infuse).

### Season queues

When the default player is Infuse and you play an episode, HomeTV sends the rest of the release as a playlist, so
Infuse plays the next episodes without coming back to HomeTV. Infuse's `play` action takes repeated
`url`/`position`/`filename` sets and plays them in order. `PlayerLauncher.infusePlaylistURL` builds that URL.

`SeasonQueuePrefetcher` fetches the other episodes' streams while you're still in the stream picker:

- It starts from `PlaybackSession.prepare`, once the show's episode list has loaded.
- It asks every enabled add-on with a `stream` resource, nearest episodes first, three requests at a time, with a
  250-request limit per picker.
- On Select, `launch` waits up to 5 seconds for the 30 episodes after the selected one, then builds the queue
  from whatever has arrived.

`SeasonQueueBuilder` is pure, so its rules are covered by `SeasonQueueBuilderTests`:

- **Same release only.** An episode's stream joins the queue only if it comes from the same add-on and shares the
  selected stream's `bingeGroup` or `infoHash`. Magnet-only streams and uncached debrid links are skipped.
- **Contiguous.** From the selected episode the queue goes forward until an episode has no matching stream, then
  backward the same way. It doesn't skip a gap. Specials are left out, and season boundaries aren't special, so a
  complete-series pack continues into the next season.
- **Selected episode first.** Infuse's scheme has no start index, so the queue is rotated: the selected episode,
  the episodes after it, then the earlier ones.
- **At most 100 entries.** In practice the release runs out first.

Without at least one other matching episode, there's no queue and the episode launches alone. If Infuse refuses the
playlist URL, `PlayerLauncher` launches the selected episode alone. VLC and System Default always get one URL.

### Adding an external player

1. Add a case to `ExternalPlayer`, with its `displayName` and the `probeURL` of its URL scheme.
2. Add the scheme to `LSApplicationQueriesSchemes` in `project.yml`, and run `xcodegen generate`.
3. Add its URL to `PlayerLauncher.launchURL`. Encode the media URL so the player's query parser can't split it.
4. Add its description to `detail(for:)` in `PlayerPickerView`.
5. If its scheme takes a start position, `PlaybackSession.prepare` must load the runtime for it: add the player to
   the `player == .infuse || player == .builtIn` check there.
6. If it can call back, give it the token's `x-success` and `x-error` URLs, register its launches in
   `PlaybackSession.launch` the way Infuse's are, and teach `PlaybackReturnCoordinator` its callback's parameter
   names. Without a callback, HomeTV records nothing about the play, so leave `willLaunch(nil)` for it.
7. Update [Picking a stream and playing it](/guide/playback/) for the new player.

## Resume and return

### `PlaybackSession`

`PlaybackSession` launches one movie or episode in the default player. `StreamPickerView` and
`ContinueWatchingResumer` both use it, so a resume from Continue Watching launches exactly like Select in the picker.

- `prepare()` runs when the picker opens. It reads the title's meta from the enabled add-ons for the runtime, the
  release year, the show name and the episode list, then starts the season prefetch for Infuse. It does nothing for
  VLC and System Default, which can't use any of it.
- `launch(_:addonID:)` works out the resume position with `PlayerLauncher.resumePosition`. Saved seconds win.
  Otherwise a saved fraction between 1% and 95% is turned into seconds with the runtime, and an unknown runtime
  starts from the beginning. The in-app player waits up to 5 seconds for the meta only when it needs the runtime;
  external players always wait for it.
- `cancel()` stops the season prefetch when the caller goes away.

### `StreamChoiceStore`

Every launch records the stream with `StreamChoiceStore.record`, keyed by the movie ID or the show ID, in
`hometv.streamChoices.v1`. A Continue Watching card uses it to play again without the picker.

`StreamChoice` stores the stream's identity, not its URL, because debrid and add-on URLs expire. On resume,
`ContinueWatchingResumer` fetches the streams again from the same add-on and calls `StreamChoice.match`:

- **Same episode:** the same file, by `infoHash` and `fileIdx`, then the `filename` hint, then the release name.
  A release-name match is skipped when its filename or hash differs. With no same-file match, it falls back to the
  same release, as for another episode.
- **Another episode,** such as the next one after you finished the last: the same release, by `bingeGroup` or
  `infoHash`, like a season queue.

If nothing matches, the add-on is disabled or the launch fails, the stream picker opens instead.

### Returning from Infuse

Before an Infuse launch, `PlaybackSession` registers it with `PlaybackReturnCoordinator.willLaunch`, along with a new
random 32-character token, the content ID, the runtime and the queue. Any other launch clears the registration.

`HomeTVApp.onOpenURL` passes every incoming link to `PlaybackReturnCoordinator.handle` first. A link whose token
doesn't match the registered launch is ignored, so another app can't record a fake result. Infuse calls back once,
when the playlist ends or you close the player:

```text
hometv://playback-done-<token>?lastPlayedUrl=<url>&position=<seconds>
```

It can't tell a finished playlist from closing the player, so `reconcile` is careful:

- With a queue, it finds the returned URL with `PlaybackQueue.index(ofEntryMatching:)`: the exact URL, or the URL
  without its query when exactly one entry matches that, since a debrid link can come back with a new token. Every
  entry before it is marked watched. If the URL matches no entry, nothing is recorded.
- The returned item gets a resume point from `position` and the runtime. With no position or no runtime, it gets
  none.

`playback-error-<token>` clears the registration without recording anything.

### Progress from the in-app player

`PlayerModel.saveProgress` saves the position every 10 seconds while playing, on pause, when the app leaves the
foreground, when the player closes, and at the end. It only saves once the stream has played, so a stream that never
started can't overwrite the resume point. The in-app player also scrobbles `start`, `pause` and `stop` to Trakt
through `TraktService`.

### `PlaybackProgress`

Both the Infuse callback and the in-app player record through `PlaybackProgress.record`:

- It saves the fraction and the seconds with `UserLibrary.recordProgress`, for the episode and for the show, since
  Continue Watching cards are keyed by the show.
- Past 95%, an episode is marked watched. Not when its runtime was borrowed from another episode, which is too rough
  to call it finished.
- The in-app player passes `scrobblesToTrakt`, because its Trakt `stop` already adds the history entry; the watched
  mark then stays on the device.

See [Trakt or the device](/developers/architecture/#trakt-or-the-device) for where progress is stored.

### Now Playing

`NowPlayingController` publishes the in-app player to `MPNowPlayingInfoCenter`, with the title, elapsed time,
duration and rate, and routes `MPRemoteCommandCenter` commands back to `PlayerModel` through the
`NowPlayingCommands` protocol. Siri, Control Center and other remotes can play, pause, skip 10 seconds, seek and
scan. `PlayerModel.start()` activates it and `stop()` removes the commands and clears the info.

KSPlayer has its own remote command handling, which `KSPlaybackEngine` turns off with
`registerRemoteControll = false`, so both engines share `NowPlayingController`. A new engine must not register remote
commands of its own.

## Testing on the Apple TV

The simulator can't play most add-on streams, so test playback changes on an Apple TV. Build and install for the
device as in [Build from source](/developers/build-from-source/), then launch from the command line with `devicectl`:

```sh
xcrun devicectl device process launch --console --terminate-existing \
  --device <device ID> \
  --environment-variables '{"PLAYER_TEST_URL":"https://example.com/video.mkv","PLAYER_TEST_TITLE":"Test"}' \
  com.hometv.HomeTV
```

`xcrun devicectl list devices` shows the device ID. The `PLAYER_*` variables are listed in
[Debug launch environment variables](/developers/build-from-source/#player).

- **Logs.** Debug builds print `[Player]` lines through `PlaybackDiagnostics`: the route, each state change, the
  FFmpeg fallback, the mode switch, saves and stalls. `--console` shows standard output, not `Logger`, which is why
  these use `print`.
- **Start time.** `PlaybackDiagnostics` logs `first frame on <route> after <time>`, measured from Select or from the
  debug launch.
- **Local files.** tvOS doesn't let the app read its Documents folder, so copy test files to Caches and set
  `PLAYER_TEST_URL` to the bare file name:

  ```sh
  xcrun devicectl device copy to --device <device ID> \
    --domain-type appDataContainer --domain-identifier com.hometv.HomeTV \
    --source sample.mkv --destination Library/Caches/sample.mkv
  ```

- **Screenshots.** `xcrun devicectl device capture screenshot --device <device ID> --destination shot.png`.
- **Trakt.** `PLAYER_TEST_ID` saves progress and scrobbles like a real title. On an Apple TV signed in to Trakt,
  that adds to your Trakt history.

Before you open a pull request, play at least an MP4 or HLS stream (the native route), an MKV (FFmpeg), a resume
from Continue Watching, and an Infuse hand-off if you changed `PlayerLauncher` or `PlaybackSession`.
