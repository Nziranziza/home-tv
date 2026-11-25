---
title: Licenses
description: HomeTV's license, the licenses of the code it ships, and the terms of the services it connects to.
---

This page covers HomeTV's own license, the third-party code bundled in the app, and the online services the app
talks to. It's a summary for people building or forking HomeTV, not legal advice. The license texts and each
service's terms decide in the end.

## HomeTV ships no content

HomeTV doesn't host, index or provide any movies, shows or streams. It shows catalogs and plays links from the
add-ons you install, and you choose those add-ons. HomeTV doesn't check or control what an add-on links to. You're
responsible for the add-ons you install and for having the right to watch what you play.

## HomeTV

HomeTV is licensed under the [GNU General Public License v3.0 or later](https://github.com/Nziranziza/home-tv/blob/main/LICENSE)
(GPL-3.0-or-later). You can use, change and share the code, including in a fork, as long as anything you distribute
stays under the same license and comes with its source code.

## Code shipped in the app

Device builds bundle two third-party frameworks for the built-in player. Simulator builds bundle neither. They use
the AVPlayer stub engine instead. See [Playback architecture](/developers/playback-architecture/).

| Component | What it does | License |
| --- | --- | --- |
| [KSPlayer](https://github.com/kingslay/KSPlayer), free build | The built-in player's engine | [GPL-3.0](https://github.com/kingslay/KSPlayer/blob/7d6b4ced6f6b0d3b54cde84c77314a3fa6d927b0/LICENSE) |
| [FFmpegKit](https://github.com/kingslay/FFmpegKit) (kingslay) | FFmpeg and the libraries KSPlayer loads: the `Libav*` libraries, `Libswresample`, `Libswscale`, `libfribidi`, `libplacebo` and `libzvbi` | [GPL-3.0](https://github.com/kingslay/FFmpegKit/blob/20e3ba2a4c36978fed7b12a56839fadd92e901ea/LICENSE) as a whole. The libraries in it keep their own licenses, listed below |

`scripts/fetch-player-frameworks.sh` downloads both into `Vendor/PlayerFrameworks`. They aren't in the repository.
The KSPlayer and FFmpegKit license links point at the exact commits the script pins.

The libraries inside those frameworks, including the ones compiled into them from FFmpegKit's static builds. System
libraries that come with tvOS, such as zlib and libxml2, aren't listed.

| Library | Inside | License |
| --- | --- | --- |
| [FFmpeg](https://ffmpeg.org) | `Libav*`, `Libswresample`, `Libswscale` | [LGPL-3.0-or-later](https://github.com/FFmpeg/FFmpeg/blob/master/LICENSE.md). This build turns on FFmpeg's version 3 option and leaves out its GPL-only parts |
| [dav1d](https://code.videolan.org/videolan/dav1d) | `Libavcodec` | [BSD-2-Clause](https://github.com/videolan/dav1d/blob/master/COPYING) |
| [Opus](https://opus-codec.org) | `Libavcodec` | [BSD-3-Clause](https://github.com/xiph/opus/blob/main/COPYING) |
| [SRT](https://github.com/Haivision/srt) | `Libavformat` | [MPL-2.0](https://github.com/Haivision/srt/blob/master/LICENSE) |
| [OpenSSL](https://www.openssl.org) | `Libavformat` | [Apache-2.0](https://github.com/openssl/openssl/blob/master/LICENSE.txt) |
| [FriBidi](https://github.com/fribidi/fribidi) | `libfribidi` | [LGPL-2.1-or-later](https://github.com/fribidi/fribidi/blob/master/COPYING) |
| [ZVBI](https://github.com/zapping-vbi/zvbi) | `libzvbi` | [GPL-2.0-or-later, with some files under other licenses](https://github.com/zapping-vbi/zvbi/blob/main/COPYING.md) |
| [libplacebo](https://code.videolan.org/videolan/libplacebo) | `libplacebo` | [LGPL-2.1-or-later](https://github.com/haasn/libplacebo/blob/master/LICENSE) |
| [Little CMS](https://github.com/mm2/Little-CMS) | `libplacebo` | [MIT](https://github.com/mm2/Little-CMS/blob/master/LICENSE) |
| [libdovi](https://github.com/quietvoid/dovi_tool) | `libplacebo` | [MIT](https://github.com/quietvoid/dovi_tool/blob/main/LICENSE) |
| [MoltenVK](https://github.com/KhronosGroup/MoltenVK) | `libplacebo` | [Apache-2.0](https://github.com/KhronosGroup/MoltenVK/blob/main/LICENSE) |
| [libass](https://github.com/libass/libass) | `KSPlayer` | [ISC](https://github.com/libass/libass/blob/master/COPYING) |
| [FreeType](https://freetype.org) | `KSPlayer` | [FreeType License or GPL-2.0-or-later](https://github.com/freetype/freetype/blob/master/LICENSE.TXT) |
| [HarfBuzz](https://harfbuzz.github.io) | `KSPlayer` | [MIT](https://github.com/harfbuzz/harfbuzz/blob/main/COPYING) |
| [Fontconfig](https://www.freedesktop.org/wiki/Software/fontconfig/) | `KSPlayer` | [MIT-style](https://gitlab.freedesktop.org/fontconfig/fontconfig/-/blob/main/COPYING) |

### What the GPL means for forks and builds

KSPlayer's free build is GPL-licensed. Any app that ships it has to be released under the GPL with its source code
available. That's why HomeTV uses the GPL too. If you distribute a build that includes the player, for example
by giving someone a signed `.ipa`:

- Keep your fork under GPL-3.0 (or a later GPL version).
- Give everyone you give the build to its complete source code, including your changes, at no extra charge. For a
  download, put the source, or clear directions to it, next to the build. You don't have to publish it to everyone.
  A written offer to send the source later is only allowed in the cases section 6 of the GPL lists, such as builds
  on physical media.
- Include HomeTV's `LICENSE` and the copyright and license notices of KSPlayer, FFmpegKit and the libraries
  FFmpegKit bundles. HomeTV's builds don't include those third-party notices today, so you have to add them
  yourself, for example in a file sent with the build.
- Don't add terms that stop the people you give the build to from changing and sharing it.

Building HomeTV for your own Apple TV isn't distribution, so these conditions don't apply to it.

There's no closed-source HomeTV build. HomeTV's own code is GPL-3.0-or-later, so a closed-source fork needs separate
permission from HomeTV's copyright holders. Every bundled component would also need a license that allows it.
KSPlayer's paid LGPL build, described in [KSPlayer's licensing post](https://github.com/kingslay/KSPlayer/issues/731),
covers only the player. It doesn't change HomeTV's license or FFmpegKit's. The paid build has different terms, so
check the license before you change `KSPLAYER_REVISION`, as [Updating KSPlayer or
FFmpeg](/developers/playback-architecture/#updating-ksplayer-or-ffmpeg) says.

## Services HomeTV connects to

HomeTV calls these services directly. Each has its own terms, and using HomeTV means using the service under them.

| Service | What HomeTV uses it for | When | Terms |
| --- | --- | --- | --- |
| [TMDB](https://www.themoviedb.org) | Artwork, cast, trailers, streaming services and In Theaters | Only when the app was built with a TMDB key | [API terms of use](https://www.themoviedb.org/api-terms-of-use) |
| [Trakt](https://trakt.tv) | Progress, watched history and watchlist sync | Only when the app was built with Trakt keys and you sign in | [Terms](https://trakt.tv/terms), [privacy policy](https://trakt.tv/privacy) |
| [TheIntroDB](https://theintrodb.org) | Intro, recap and credits times for Skip Intro | Every time a title plays in the built-in player | [Terms](https://theintrodb.org/terms) |
| [IntroDB](https://introdb.app) | Intro, recap and credits times for Skip Intro. When both have a title, TheIntroDB's times win | With TheIntroDB, at the same time | [API docs](https://introdb.app/docs), [open data](https://api.introdb.app/open-data/) |
| [YouTube](https://www.youtube.com) | Trailer thumbnails from TMDB, and opening a trailer in the YouTube app | Only with a TMDB key, for titles whose trailers no installed add-on, such as Trailerio, provides | [Terms of service](https://www.youtube.com/t/terms) |
| Metahub (`images.metahub.space`) | Posters, backgrounds and logos for titles that come from Trakt, such as your watchlist and Trakt progress | When you're signed in to Trakt, whatever add-ons are installed | No published terms |

### TMDB attribution

TMDB's terms ask every app that uses its API to credit TMDB with its logo and a disclaimer. When the app is built
with a TMDB key, **Settings** shows this row, which can't be selected:

> **Metadata provided by TMDB**
> This product uses the TMDB API but is not endorsed or certified by TMDB.

The logo in the row is TMDB's own, used as their
[logo and attribution guidelines](https://www.themoviedb.org/about/logos-attribution) describe. Keep the row if you
fork HomeTV and use a TMDB key. See [Metadata provided by TMDB](/guide/top-shelf-settings-faq/#metadata-provided-by-tmdb).

### Your own API keys

HomeTV doesn't come with TMDB or Trakt keys. Whoever builds the app adds their own in `Secrets.xcconfig`, as
[Optional: TMDB and Trakt keys](/guide/setup-and-addons/#optional-tmdb-and-trakt-keys) describes, and accepts that
service's API terms for them. Never commit the keys or ship them in a build you give to someone else.

## Add-ons

Add-ons are separate services run by other people, and each sets its own terms. Check an add-on's terms before you
install it. HomeTV lists three in **Settings → Addons** so they can be installed in one step:

| Add-on | What it adds | Run by | Terms |
| --- | --- | --- | --- |
| Cinemeta | Movie and series catalogs and details. Installed on first launch | Stremio | [Stremio terms](https://www.stremio.com/tos) |
| OpenSubtitles v3 | Subtitles from [OpenSubtitles](https://www.opensubtitles.com) | Stremio | [Stremio terms](https://www.stremio.com/tos) |
| WatchHub | Links to streaming services that carry a title | Stremio | [Stremio terms](https://www.stremio.com/tos) |

## Other apps

Infuse and VLC are separate apps from the App Store, each under its own license. HomeTV only hands them a stream link
when you pick them as the player. Neither is bundled with HomeTV.

## Build tools

[XcodeGen](https://github.com/yonaskolb/XcodeGen) and [SwiftLint](https://github.com/realm/SwiftLint) (both MIT) are
used to build and lint HomeTV. Neither ships in the app.
