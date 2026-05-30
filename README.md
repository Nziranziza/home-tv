# HomeTV

An Apple TV streaming app. Browses Stremio addons, hands playback off to Infuse (default) or VLC.

## What it does

- **Browse** — Watch Now shows a hero shelf and one row per addon catalog.
- **Search** — Queries every installed addon that exposes a `search` extra.
- **Detail** — Backdrop, synopsis, episode list for series.
- **Play** — Picks a stream from all addons, opens it in Infuse (or VLC / system default).

## Stack

- tvOS 18 target, Xcode 26.3, Swift 5.10, SwiftUI.
- No third-party Swift dependencies.
- [xcodegen](https://github.com/yonaskolb/XcodeGen) generates `HomeTV.xcodeproj` from `project.yml`.

## Build

Prereqs: Xcode 26.3 with the **tvOS platform** installed (`xcodebuild -downloadPlatform tvOS` if missing), and `xcodegen` (`brew install xcodegen`).

```sh
cd ~/Desktop/HomeTV
xcodegen generate
open HomeTV.xcodeproj
```

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

1. Install **Infuse** on the Apple TV from the App Store.
2. Launch HomeTV. Cinemeta is seeded automatically; if your Apple TV is offline at first launch, open Settings → Addons and tap Install on `https://v3-cinemeta.strem.io/manifest.json`.
3. Add stream-providing addons in Settings → Addons. Manifest URLs end in `/manifest.json`.

**Entering URLs is painful with the remote.** When the keyboard appears on the Apple TV, your iPhone should buzz with a Continuity Keyboard prompt — tap it and type from the phone.

## How playback works

When you pick a stream, HomeTV builds an `infuse://x-callback-url/play?url=...` URL and asks tvOS to open it. Infuse takes over from there. For magnet links from torrent-providing addons, the magnet URI is passed through directly — Infuse handles those natively.

Switch the default player in Settings → Default Player. VLC handles direct HTTP streams; for magnet streams you need Infuse.

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
