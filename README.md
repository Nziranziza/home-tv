# HomeTV

A native Apple TV app in SwiftUI with an Apple TV app–style interface. It browses and plays from Stremio add-ons,
plays in its own player (KSPlayer, with AVPlayer for Dolby Vision and Atmos), adds TMDB metadata, and syncs with Trakt.
Infuse and VLC remain optional.

![Watch Now](docs/src/assets/screenshots/watch-now.jpg)

| Title detail | Search | Player |
| --- | --- | --- |
| ![Title detail](docs/src/assets/screenshots/detail.jpg) | ![Search](docs/src/assets/screenshots/search.jpg) | ![Player](docs/src/assets/screenshots/player.jpg) |

## Documentation

Everything lives on the docs site, **[hometv.nziranziza.dev](https://hometv.nziranziza.dev/)**:

- [Install HomeTV](https://hometv.nziranziza.dev/guide/install/) on your Apple TV
- [User guide](https://hometv.nziranziza.dev/guide/setup-and-addons/), starting with setup and add-ons
- [Build from source](https://hometv.nziranziza.dev/developers/build-from-source/), for development

## Quick start

Needs Xcode 26.3 with the tvOS platform and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
cp Secrets.example.xcconfig Secrets.xcconfig   # optional keys, fine to leave blank
scripts/fetch-player-frameworks.sh             # device builds only
xcodegen generate
open HomeTV.xcodeproj
```

Pick the **HomeTV** scheme and an Apple TV 4K simulator, then press ⌘R.
