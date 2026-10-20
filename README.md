# HomeTV

An Apple TV streaming app. Browses Stremio addons, hands playback off to Infuse (default) or VLC.

## What it does

- **Browse** — Watch Now shows a hero shelf and one row per addon catalog.
- **Search** — Queries every installed addon that exposes a `search` extra.
- **Detail** — Backdrop, synopsis, episode list for series.
- **Play** — Picks a stream from all addons and plays it in HomeTV's own player (or hands it to Infuse, VLC or the system default).

## Stack

- tvOS 26 target, Xcode 26.3, Swift 5.10, SwiftUI.
- In-app playback uses [KSPlayer](https://github.com/kingslay/KSPlayer)'s free GPL build (prebuilt, Apple TV only), fetched into `Vendor/` by a script.
- [xcodegen](https://github.com/yonaskolb/XcodeGen) generates `HomeTV.xcodeproj` from `project.yml`.

## Build

Prereqs: Xcode 26.3 with the **tvOS platform** installed (`xcodebuild -downloadPlatform tvOS` if missing), and `xcodegen` (`brew install xcodegen`).

```sh
cd ~/Desktop/HomeTV
scripts/fetch-player-frameworks.sh   # once, and again after its pinned versions change
xcodegen generate
open HomeTV.xcodeproj
```

The player frameworks only have an Apple TV slice, so device builds link them and simulator builds
skip them and play through a plain AVPlayer stand-in (MP4 and HLS only). A device build without them
fails with a message to run the script.
In Debug builds, set the `PLAYER_TEST_URL` environment variable (scheme → Run → Arguments) to open the
player on that URL at launch, e.g. Apple's sample HLS stream for checking player UI in the simulator.
`PLAYER_TEST_TITLE` and `PLAYER_TEST_LOGO` (an image URL) fill its loading screen.

Pick scheme **HomeTV**, destination **Apple TV 4K (3rd generation)** (any tvOS Simulator works), and ⌘R.

Command-line:

```sh
xcodebuild -project HomeTV.xcodeproj -scheme HomeTV \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
  -configuration Debug build
```

After adding or moving Swift files, re-run `xcodegen generate` before building.

## Sideload to your Apple TV

1. Apple TV → Settings → Remotes and Devices → Remote App and Devices → leave that screen open.
2. Mac → Xcode → Window → Devices and Simulators → your Apple TV should appear and pair.
3. In Xcode, set the **HomeTV** target's **Signing & Capabilities** team to your personal Apple ID team and change `PRODUCT_BUNDLE_IDENTIFIER` (in `project.yml`) to something unique like `com.<yourname>.hometv` — re-run `xcodegen generate` after editing.
4. Pick your Apple TV as the run destination → ⌘R.

**Free Apple Developer account caveat:** the signed `.app` expires after 7 days. Re-run Build & Run weekly. A paid account ($99/yr) bumps that to 1 year.

## First-run setup

1. Launch HomeTV. Cinemeta is seeded automatically; if your Apple TV is offline at first launch, open Settings → Addons and tap Install on `https://v3-cinemeta.strem.io/manifest.json`.
2. Add stream-providing addons in Settings → Addons. Manifest URLs end in `/manifest.json`.

**Entering URLs is painful with the remote.** When the keyboard appears on the Apple TV, your iPhone should buzz with a Continuity Keyboard prompt — tap it and type from the phone.

## How playback works

When you pick a stream, HomeTV plays it in its own player, KSPlayer. MKV, AVI and WebM start on its FFmpeg decoder; everything else starts on AVPlayer, which keeps native Dolby Vision and Atmos, and moves to FFmpeg if AVPlayer can't play it. Direct HTTP streams only; magnet links need an external player.

Infuse and VLC are optional, chosen in Settings → Default Player. With Infuse (installed from the App Store), HomeTV builds an `infuse://x-callback-url/play?url=...` URL and hands the stream over, magnet links included. VLC handles direct HTTP streams only.

## Project layout

```
HomeTV/
├── HomeTVApp.swift              # @main entry
├── Views/
│   ├── RootTabView.swift        # 4 top tabs
│   ├── WatchNow/                # HeroShelf, ContentRow, WatchNowView
│   ├── Detail/                  # MetaDetailView, StreamPickerView
│   ├── Search/                  # SearchView
│   ├── Library/                 # placeholder
│   ├── Settings/                # SettingsView, AddonManagerView, PlayerPickerView
│   └── Components/              # PosterCard
├── Services/
│   ├── Stremio/                 # Models, StremioClient, AddonRegistry
│   └── Player/                  # ExternalPlayer, PlayerLauncher, PlayerPreference
└── Assets.xcassets/
```

Addon list and default player are persisted in `UserDefaults` (`hometv.addons.v1`, `hometv.defaultPlayer.v1`).

## What's intentionally not here yet

- **CloudStream support.** CloudStream plugins are Kotlin/Android — they don't run on tvOS. Deferred until there's a clear path (companion server or native ports).
- **App Store distribution.** Not currently set up; install by sideloading (see above).
- **App icon and Top Shelf.** Placeholder. Drop layered PNGs into `Assets.xcassets/App Icon & Top Shelf Image.brandassets/` and re-enable `ASSETCATALOG_COMPILER_APPICON_NAME` in `project.yml` when you're ready.
- **Continue Watching / watch history.** Library tab is a placeholder.
