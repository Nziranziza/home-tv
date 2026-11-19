# HomeTV

A native Apple TV app in SwiftUI with an Apple TV app–style interface. It browses and plays from Stremio add-ons,
plays in its own player (KSPlayer, with AVPlayer for Dolby Vision and Atmos), adds TMDB metadata, and syncs with Trakt.
Infuse and VLC remain optional.

![Watch Now](docs/screenshots/watch-now.jpg)

| Title detail | Search | Player |
| --- | --- | --- |
| ![Title detail](docs/screenshots/detail.jpg) | ![Search](docs/screenshots/search.jpg) | ![Player](docs/screenshots/player.jpg) |

## What it does

### Browse
- **Watch Now** has a full-bleed hero carousel with trailer autoplay, then rows for Continue Watching, every add-on
  catalog, In Theaters & At Home, Explore Channels & Apps, Browse by Genre and Recently Watched.
- **Row preview.** Opening a catalog row expands its card into a paged gallery with the title's hero, a thumbnail strip
  and its trailer.
- **Channels** gives a streaming service (Netflix, HBO Max, …) its own screen with a Top 10 and themed shelves, built
  from TMDB.
- **Genres** opens a poster grid per genre.
- **Top Shelf** shows a carousel with trailers that deep-links into titles.

### Titles
- **Detail screens** for movies and shows: a hero that collapses as you scroll, Episodes by season, Trailers, Cast &
  Crew, How to Watch, Related and Information. Cinemeta supplies the base data and TMDB fills in what it lacks.
- **Episode detail** and **cast/person** screens with a filmography.
- **Stream picker** collects streams from all add-ons and shows quality, size, audio and subtitle languages, and debrid
  cached status. It remembers the stream you picked for each title.

### Search
- Searches every add-on with a `search` extra, plus cast. Results are ranked, with a Top Results section, a section
  per type and suggestions.

### Player
HomeTV's own player is built on the transport bar, menus and behaviour of Apple's player:
- **Engines.** MKV, AVI and WebM start on KSPlayer's FFmpeg decoder. Everything else starts on AVPlayer, which keeps
  native Dolby Vision and Atmos, and moves to FFmpeg if AVPlayer can't play it. Match Content frame rate and dynamic
  range switching is supported.
- **Transport.** Scrubbing with thumbnail previews, 4-speed scan, skip back/forward, chapters, and Now Playing / Siri
  Remote commands.
- **Subtitles.** Embedded tracks, add-on tracks and subtitle add-ons such as OpenSubtitles, ranked against the
  release. Also timing adjustment, caption styles and per-title defaults.
- **Audio.** Track selection, Enhance Dialogue and Reduce Loud Sounds.
- **Info and Continue Watching tabs.** From Beginning, Go to Movie/Show, and switching titles without leaving
  the player.
- **Skip Intro / Recap / Credits** from chapter markers, IntroDB and TheIntroDB.
- **Up Next** for episodes: the video shrinks to a corner over the next episode with a countdown.
- **Resume.** Positions are saved, and progress is scrobbled to Trakt.

### Library and sync
- **Library** holds Continue Watching and your Watchlist. It is stored on the device, or comes from Trakt when you are
  signed in so it syncs with other players.
- **Trakt** handles sign-in, scrobbling, watched state, watchlist and Up Next.

### External players
Infuse, VLC or the system default can be chosen in Settings → Default Player. Infuse gets the whole season as a queue
and is the way to play magnet links.

## Stack

- tvOS 26, Xcode 26.3, Swift 5.10, SwiftUI with `@Observable`.
- In-app playback uses [KSPlayer](https://github.com/kingslay/KSPlayer)'s free GPL build (prebuilt, Apple TV only).
  A script fetches it into `Vendor/`.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) generates `HomeTV.xcodeproj` from `project.yml`. The project is
  gitignored.
- Data sources: Stremio add-ons (catalogs, meta, streams, subtitles), [TMDB](https://www.themoviedb.org) (enrichment,
  channels, cast), [Trakt](https://trakt.tv) (sync), IntroDB and TheIntroDB (skip segments), and a trailer add-on.

## Build

Prerequisites: Xcode 26.3 with the **tvOS platform** installed (run `xcodebuild -downloadPlatform tvOS` if it's
missing), and `xcodegen` (`brew install xcodegen`).

```sh
cp Secrets.example.xcconfig Secrets.xcconfig   # then fill in what you have
scripts/fetch-player-frameworks.sh             # once, and again after its pinned versions change
xcodegen generate
open HomeTV.xcodeproj
```

`Secrets.xcconfig` (gitignored) holds:

| Key | Needed for | If blank |
| --- | --- | --- |
| `DEVELOPMENT_TEAM` | Device builds (signs every target) | Simulator still works |
| `TMDB_API_KEY` | Enrichment, channels, cast, In Theaters | Those features don't run |
| `TRAKT_CLIENT_ID` / `TRAKT_CLIENT_SECRET` | Trakt sign-in and sync | Trakt row is hidden; library stays on the device |

Pick the **HomeTV** scheme and an Apple TV 4K simulator, then press ⌘R. From the command line:

```sh
xcodebuild -project HomeTV.xcodeproj -scheme HomeTV \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
  -configuration Debug build
```

After adding or moving Swift files, run `xcodegen generate` again before building.

**Simulator vs. device.** The player frameworks only have an Apple TV slice. Device builds link them. Simulator builds
skip them and play through a plain AVPlayer stand-in, which handles MP4 and HLS only. A device build without the
frameworks fails with a message telling you to run the script.

**Player test hooks (Debug).** Set `PLAYER_TEST_URL` (scheme → Run → Arguments) to open the player on that URL at
launch, for example Apple's sample HLS stream. `PLAYER_TEST_TITLE` and `PLAYER_TEST_LOGO` (an image URL) fill in its
loading screen.

**Tests.** `HomeTVTests` holds the unit tests (player, queueing, subtitles, skip segments, search ranking, Trakt
scrobbling and more). `HomeTVUITests` holds the focus-engine UI tests.

## Sideload to your Apple TV

1. On the Apple TV, open Settings → Remotes and Devices → Remote App and Devices and leave that screen open.
2. On the Mac, open Xcode → Window → Devices and Simulators. Your Apple TV should appear there; pair it.
3. Set `DEVELOPMENT_TEAM` in `Secrets.xcconfig`. Change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` to something
   unique, such as `com.<yourname>.hometv`, for the app and the Top Shelf extension. Also replace the App Group
   `group.com.hometv.HomeTVs` with your own (it must start with `group.`, and App Group IDs are unique across all
   teams). It appears in five places, and all five must match or the app and Top Shelf stop sharing data:
   both targets' entitlements in `project.yml`, `HomeTV/HomeTV.entitlements`,
   `HomeTVTopShelf/HomeTVTopShelf.entitlements` and `HomeTV/Services/Shared/TopShelfSharedState.swift`.
   Then run `xcodegen generate`.
4. Pick your Apple TV as the run destination and press ⌘R.

**Free Apple Developer account caveat:** the signed app expires after 7 days, so build and run again each week. A paid
account ($99/yr) extends that to 1 year.

## First-run setup

1. Launch HomeTV. Cinemeta is added automatically. If the Apple TV was offline at first launch, connect it to the
   internet, then open Settings → Addons and install `https://v3-cinemeta.strem.io/manifest.json`.
2. Add stream, subtitle and trailer add-ons in Settings → Addons. Manifest URLs end in `/manifest.json`.
3. Optionally, connect Trakt in Settings.

**Typing URLs with the remote is painful.** When the keyboard appears, your iPhone should show a Continuity Keyboard
prompt. Tap it and type on the phone.

## Project layout

```
HomeTV/
├── HomeTVApp.swift
├── Navigation/            # Deep links (Top Shelf, debug hooks)
├── Views/
│   ├── RootTabView.swift  # Search, Watch Now, Library, Settings
│   ├── WatchNow/          # Hero carousel, rows, RowPreview gallery
│   ├── Detail/            # Title + episode detail, stream picker
│   ├── Channel/ Genre/ Cast/ Search/ Library/ Settings/
│   ├── Player/            # Transport, Subtitles, Audio, Info, Skip, UpNext
│   └── Components/        # Shared cards, hero pieces, theme
├── Services/
│   ├── Stremio/           # Add-on client and registry
│   ├── TMDB/              # Enrichment, channels, people
│   ├── Trakt/             # OAuth, sync, scrobbling
│   ├── Player/            # PlaybackEngine (AV/KS), queue, subtitles, audio, skip, Up Next
│   ├── Trailers/ Images/ Storage/ Shared/
HomeTVTopShelf/            # Top Shelf extension
HomeTVTests/ HomeTVUITests/
scripts/                   # fetch-player-frameworks.sh
```

## Not here yet

- **CloudStream support.** CloudStream plugins are Kotlin/Android and don't run on tvOS.
- **App Store distribution.** Install by sideloading (see above).
- **Magnet links in the built-in player.** Direct HTTP streams only; use Infuse for magnets.
