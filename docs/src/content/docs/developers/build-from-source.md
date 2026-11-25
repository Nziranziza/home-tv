---
title: Build from source
description: Set up a development checkout of HomeTV and run it in the simulator or on an Apple TV.
---

This page gets a fresh clone building and running in the tvOS simulator. To put the app on an Apple TV, follow
[Install HomeTV](/guide/install/), which also covers signing, bundle identifiers and the App Group.

## Prerequisites

- **Xcode 26.3** or later with the **tvOS platform**. Add the platform in **Xcode → Settings → Components**, or run
  `xcodebuild -downloadPlatform tvOS`.
- **[XcodeGen](https://github.com/yonaskolb/XcodeGen)**, which creates the Xcode project: `brew install xcodegen`.

## Quick start

```sh
git clone https://github.com/Nziranziza/home-tv.git
cd home-tv
cp Secrets.example.xcconfig Secrets.xcconfig   # fill in what you have, or leave it blank
scripts/fetch-player-frameworks.sh             # needed for device builds only
xcodegen generate
open HomeTV.xcodeproj
```

Pick the **HomeTV** scheme and an **Apple TV 4K** simulator, then press **⌘R**. The app starts with Cinemeta
installed, so Watch Now fills in without any keys.

## The Xcode project is generated

`HomeTV.xcodeproj` is created by XcodeGen from `project.yml` and is gitignored. Don't edit project settings in
Xcode: change `project.yml` and regenerate. Run `xcodegen generate` again after you:

- add, move or delete a Swift file,
- change `project.yml`,
- change `Secrets.xcconfig`.

A build that can't find a type you just added usually means the project wasn't regenerated.

## Secrets

`Secrets.xcconfig` is gitignored. Copy it from `Secrets.example.xcconfig`. Every key is optional, and the app builds
and runs with all of them blank.

| Key | Where to get it | Needed for | If blank |
| --- | --- | --- | --- |
| `DEVELOPMENT_TEAM` | Your Apple team ID. See [Set your signing team](/guide/install/#4-set-your-signing-team). | Device builds | The simulator still works |
| `TMDB_API_KEY` | The v3 **API Key** (32 characters) at [themoviedb.org/settings/api](https://www.themoviedb.org/settings/api), not the v4 Read Access Token | Artwork and data enrichment, channels, cast, In Theaters & At Home | Those features don't run |
| `TRAKT_CLIENT_ID`, `TRAKT_CLIENT_SECRET` | Create an app at [trakt.tv/oauth/applications](https://trakt.tv/oauth/applications) with the redirect URI `urn:ietf:wg:oauth:2.0:oob` | Trakt sign-in and sync | The Trakt row is hidden and the library stays on the device |

The values reach the app through the generated `Info.plist`, so regenerate the project after you change them.

## Simulator and device

The built-in player runs on [KSPlayer](https://github.com/kingslay/KSPlayer) and FFmpeg. Their prebuilt frameworks
have an Apple TV slice only, no simulator slice, so the two kinds of build differ:

- **Device builds** link the frameworks from `Vendor/PlayerFrameworks`. Download them with
  `scripts/fetch-player-frameworks.sh`, and run it again when its pinned versions change. It fetches only the
  framework files, not the repositories' history. Without them, the build stops with *Player frameworks missing.
  Run scripts/fetch-player-frameworks.sh, then rebuild.*
- **Simulator builds** skip the frameworks and play through a plain AVPlayer stand-in. It plays MP4 and HLS only, so
  most add-on streams won't play in the simulator. Test playback on an Apple TV.

`Vendor/` is gitignored.

## Command-line builds

Build for the simulator with the target, not the scheme:

```sh
xcodebuild -project HomeTV.xcodeproj -target HomeTV -sdk appletvsimulator -configuration Debug build
```

This writes the app to `./build/Debug-appletvsimulator/HomeTV.app`, not to DerivedData. Install and launch it from
there:

```sh
xcrun simctl install booted build/Debug-appletvsimulator/HomeTV.app
xcrun simctl launch booted com.hometv.HomeTV
```

Use your own bundle identifier if you changed it. Xcode's Run button and `xcodebuild -scheme` builds go to
DerivedData instead, so after a scheme build, installing from `./build` installs an old copy.

`./build` is gitignored.

## Tests

The **HomeTV** scheme runs both test targets:

- **HomeTVTests**: unit tests for the player, queueing, subtitles, skip segments, search ranking, Trakt scrobbling
  and more.
- **HomeTVUITests**: UI tests that drive the focus engine.

```sh
xcodebuild test -project HomeTV.xcodeproj -scheme HomeTV \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)'
```

To run one target, add `-only-testing:HomeTVTests`.

## Debug launch environment variables

These variables open a screen or load test data at launch, so you can check a view without navigating to it with
the remote. Set them in **Product → Scheme → Edit Scheme… → Run → Arguments → Environment Variables**, in a UI test's
`app.launchEnvironment`, or with `SIMCTL_CHILD_` in front of the name when you launch from the command line:

```sh
SIMCTL_CHILD_INITIAL_TAB=search SIMCTL_CHILD_INITIAL_SEARCH=dune \
  xcrun simctl launch booted com.hometv.HomeTV
```

Content IDs are the ones add-ons use, such as `tt0111161` for a movie or `tt0944947:1:1` for an episode.

### Screens

| Variable | Value | Effect |
| --- | --- | --- |
| `INITIAL_TAB` | `library`, `search` or `settings` | Opens that tab. Anything else opens Watch Now. |
| `INITIAL_DETAIL` | `<type>:<id>`, for example `movie:tt0111161` | Pushes that title's detail screen onto Watch Now. |
| `SCROLL_TO` | `related`, `about` or `information` | On a detail screen, scrolls to that section once related titles load. Use with `INITIAL_DETAIL`. |
| `INITIAL_STREAM_PICKER` | `<type>:<id>` or `<type>:<id>:<title>` | Opens the stream picker on a detail screen. Use with `INITIAL_DETAIL`. |
| `INITIAL_SEARCH` | Any text | Opens Search with the query already typed. Use with `INITIAL_TAB=search`. |
| `INITIAL_SETTINGS` | `addons` or `player` | Opens Settings → Addons or Settings → Default Player. Use with `INITIAL_TAB=settings`. |

### Test data

| Variable | Value | Effect |
| --- | --- | --- |
| `MOCK_HERO` | A number, for example `5` | Fills the Watch Now hero with that many placeholder titles instead of a live catalog. The hero UI tests use it. |
| `MOCK_STREAMS` | `1` | The stream picker shows sample streams instead of asking add-ons, and the episode and runtime lookups before playback are skipped. |
| `SEED_HISTORY` | `1` | Adds sample titles to the local watch history if it's empty, so Continue Watching has items when you're signed out of Trakt. |
| `RESET_HISTORY` | `1` | Clears the local watch history at launch. Runs before `SEED_HISTORY`. |

### Player

These are compiled into Debug builds only.

| Variable | Value | Effect |
| --- | --- | --- |
| `PLAYER_TEST_URL` | A URL, or a file name in the app's Caches folder | Opens the player on it at launch. Put files in Caches with `xcrun devicectl device copy to`. |
| `PLAYER_TEST_TITLE` | Text | The title on the loading screen and above the transport bar. |
| `PLAYER_TEST_LOGO` | An image URL | The logo on the loading screen. |
| `PLAYER_TEST_TYPE` | `movie` or `series` | The content type. Defaults to `movie`. |
| `PLAYER_TEST_EPISODE` | Text, for example `S1, E1` | The episode line above the title in the transport bar. |
| `PLAYER_TEST_ID` | A content ID | Saves and resumes the position like a real title, and asks subtitle add-ons for subtitles. |
| `PLAYER_TEST_FILENAME` | A release file name | Ranks subtitle add-on results against it. Use with `PLAYER_TEST_ID`. |
| `PLAYER_TEST_START` | Seconds | Starts at that position, overriding the saved one. |
| `PLAYER_TEST_SUBTITLES` | `<lang>=<url or file>,…`, for example `eng=https://…/en.srt,fre=fr.srt` | Adds external subtitle files. A bare file name is read from Caches. The language is optional. |
| `PLAYER_TEST_PREWARM_MS` | Milliseconds | Prepares the stream that long before opening it, as a focused stream picker row does. |
| `PLAYER_NO_PREWARM` | `1` | Turns off preparing a stream while its row in the stream picker has focus. |
| `PLAYER_NO_RESOLVE` | `1` | Opens FFmpeg streams without first following their redirects to the final URL. |
| `PLAYER_STOCK_OPTIONS` | `1` | Uses KSPlayer's default buffering options instead of HomeTV's, to compare the two. |

For example, to check the player in the simulator, set `PLAYER_TEST_URL` to Apple's sample HLS stream,
`https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8`.
