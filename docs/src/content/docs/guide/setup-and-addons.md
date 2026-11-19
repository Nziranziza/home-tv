---
title: Setup and add-ons
description: First-run setup, installing add-ons and managing them.
---

HomeTV doesn't come with any movies, shows or streams of its own. Everything it shows comes from add-ons. Add-ons
are small web services that follow the Stremio add-on format. This page takes you from a fresh install to a title
you can play.

## What add-ons do

Each add-on provides one or more of these:

- **Catalogs.** Lists of movies and shows, with their posters, descriptions and episodes. They fill the rows on
  Watch Now and the results in Search. HomeTV installs **Cinemeta**, a catalog add-on, the first time it opens.
- **Streams.** Links to the video for a title or episode. Without a stream add-on, Play has nothing to play.
  HomeTV doesn't install one for you.
- **Subtitles.** Subtitle files for the player, such as **OpenSubtitles v3**.
- **Trailers.** The trailers that play on Watch Now, on title pages and on the Top Shelf come from the
  **Trailerio** add-on. See [Trailers](#trailers).

Add-ons are run by other people, not by HomeTV. What a stream add-on finds, and whether you're allowed to watch it,
depends on the add-on and on where you live.

## First launch

When HomeTV opens for the first time, it installs Cinemeta and Watch Now fills with rows such as Popular Movies and
Popular TV Shows. You can browse and search straight away.

If Watch Now says **No addons installed**, HomeTV couldn't reach Cinemeta. Check that the Apple TV is online, then
install Cinemeta from **Settings → Addons → Community Addons**.

## Install a stream add-on

To play anything you need a stream add-on. Every add-on has a manifest URL: a web address that ends in
`/manifest.json`. That's what you give HomeTV.

### 1. Find an add-on

HomeTV works with add-ons made for [Stremio](https://www.stremio.com), so any Stremio add-on can be installed. To
find one, browse [stremio-addons.net](https://stremio-addons.net), a community directory of public add-ons. You can
search it or browse categories such as Movies & Series and Subtitles. Each add-on's page shows its manifest URL and
whether it's online.

The directory is run by the Stremio community, not by HomeTV or Stremio. Read an add-on's description before you
install it, and check that you're allowed to watch what it finds.

Streams that are torrent magnet links don't play in HomeTV's built-in player. To play them, set
**Settings → Default Player** to Infuse.

### 2. Get the add-on's manifest URL

On the add-on's page in the directory, or on its own website, find the manifest URL. Many add-ons have a configure
page where you pick options first. When you're done, the page shows an **Install** button and a manifest URL.

- If the page shows the URL, copy it.
- If it only has an **Install** button, copy the button's link instead. On iPhone, touch and hold the button and
  tap **Copy Link**. The link starts with `stremio://`. Change that to `https://` before you use it.

The URL must start with `https://` (or `http://`) and end with `/manifest.json`, for example
`https://example-addon.com/manifest.json`. A configured add-on has a longer URL with your options in the middle.
Keep all of it.

### 3. Add it in HomeTV

1. Open **Settings → Addons**.
2. Select **Add by manifest URL**. A text field and an **Install Typed URL** button appear below it.
3. Select **Manifest URL** and enter the URL. Typing it with your iPhone is much easier than with the remote. See
   [Typing URLs with your iPhone](#typing-urls-with-your-iphone).
4. Select **Install Typed URL**.

HomeTV downloads the add-on's manifest and shows **Installed** followed by the add-on's name. The add-on appears
under **Installed** at the bottom of the screen. If an error shows instead, see
[Troubleshooting](#troubleshooting).

### 4. Play something

Go back to Watch Now or Search, open a title and select **Play**. HomeTV asks every installed add-on for streams and
lists them by source and quality. Pick one and it starts playing. [Picking a stream](/guide/playback/) covers the
list and the player.

## Typing URLs with your iPhone

When a text field is selected on the Apple TV, an iPhone signed in to the same Apple Account shows an
**Apple TV Keyboard** notification. Tap it and the iPhone's keyboard types into the Apple TV. You can also open the
**Apple TV Remote** from Control Center on the iPhone while the text field is selected.

The iPhone keyboard can paste, so you can copy the manifest URL on your iPhone and paste it straight in. This is the
quickest way to enter a long, configured URL.

If no notification appears, check that the iPhone is on the same Wi-Fi network as the Apple TV and signed in to the
same Apple Account. The Apple TV Remote in Control Center works on any iPhone that's been set up as a remote for
that Apple TV.

## Community Addons

The top of **Settings → Addons** lists a few public add-ons you can install with one click:

| Add-on | What it adds |
| --- | --- |
| Cinemeta | The main movie and show catalogs. Installed on first launch. |
| OpenSubtitles v3 | Subtitles for the player. |
| WatchHub | Links to legal streaming services that carry a title. |

Select one to install it. Installed add-ons show **Installed** with a green check.

## Manage installed add-ons

Every add-on you install is listed under **Installed** at the bottom of **Settings → Addons**, with its name,
description and manifest URL.

### Turn an add-on off

Each add-on has a switch. Turn it off and HomeTV stops using the add-on everywhere: its Watch Now rows, search
results, streams and trailers go away. Turn it back on to bring them back. The add-on stays installed, along with
its configured URL.

### Remove an add-on

Select the trash button, then **Confirm**. Select **Cancel** to keep it.

### Order

Add-ons stay in the order you installed them. Watch Now shows each add-on's catalog rows in that order, so the
first add-on's rows come first, and the hero carousel at the top shows titles from the first add-on's first
catalog. There's no way to drag add-ons into a different order yet. To move an add-on to the
end, remove it and install it again. Removing an add-on also deletes its manifest URL from HomeTV, so if you
configured it, write down the full URL shown under **Installed** before you remove it, and install that URL.

## Trailers

HomeTV plays trailers only when the Trailerio add-on is installed and turned on. Install it from its manifest URL:

```
https://trailerio.cc/manifest.json
```

Trailers then play inside HomeTV: in the Watch Now hero, on title pages and on the Apple TV Top Shelf.

Without Trailerio, the Watch Now hero and the Top Shelf show still artwork instead. Title pages still list
trailers from TMDB if you've added a [TMDB key](#optional-tmdb-and-trakt-keys). Selecting one opens it in the
YouTube app, if it's installed on the Apple TV.

## Refresh an add-on

HomeTV downloads an add-on's manifest once, when you install it, and keeps that copy. The manifest tells HomeTV
which catalogs the add-on has and which ones can be searched. If an add-on changes after you installed it, HomeTV
doesn't notice, and its rows or search results can come back empty.

To fix that, install the add-on again:

- For a Community Addon, select it in **Community Addons** again, even though it says **Installed**.
- For any other add-on, enter the same manifest URL under **Add by manifest URL** and select
  **Install Typed URL**.

The add-on keeps its place in the list. Installing it again also turns it back on, so if you had turned it off,
turn it off again afterwards. This is also how you change an add-on's options: configure it again on its
website and install the new URL. It usually replaces the old one. If both show up under **Installed**, remove
the old one.

## Optional: TMDB and Trakt keys

`Secrets.xcconfig`, which you created while [installing HomeTV](/guide/install/#3-get-the-code), has two optional
sets of keys. Add them, run `xcodegen generate` and build again.

- **`TMDB_API_KEY`** turns on extra details from [TMDB](https://www.themoviedb.org): the In Theaters & At Home row,
  the streaming channel rows such as Netflix and HBO Max, and fuller cast, artwork and episode information. Create
  a free account, then request an API key under
  [Settings → API](https://www.themoviedb.org/settings/api). Use the short **API Key**, not the long API Read
  Access Token.
- **`TRAKT_CLIENT_ID`** and **`TRAKT_CLIENT_SECRET`** turn on Trakt sync. Create an app at
  [trakt.tv/oauth/applications](https://trakt.tv/oauth/applications) with the redirect URI
  `urn:ietf:wg:oauth:2.0:oob` and copy its Client ID and Client Secret. A **Trakt** row then appears in Settings.
  [Trakt and Library](/guide/trakt-and-library/) covers signing in.

Without them, HomeTV still browses, searches and plays. Add-ons don't need either key.

## Troubleshooting

### "Enter a full https:// URL"

The text doesn't start with `https://` or `http://`. If it starts with `stremio://`, change that part to `https://`.

### "Addon returned HTTP 404" or another HTTP error

There's no add-on at that address. Check the URL for typos and make sure it ends with `/manifest.json`. Some add-ons
need you to configure them on their website first.

### "Failed to decode addon response"

The address answered, but not with an add-on manifest. This usually means the URL is the add-on's website rather
than its manifest URL.

### "Network error"

The Apple TV couldn't reach the add-on. Check the Apple TV's connection. If other add-ons work, the add-on's server
may be down. Try again later.

### Play says "No Streaming Add-ons"

All your add-ons that are turned on provide catalogs or subtitles but not streams. Install a stream add-on, or turn
yours back on.

### Play says "No Streams Found"

Your stream add-ons had nothing for this title. Select **Try Again**, try another title, or add another stream
add-on.

### Play says "Can't Reach Add-ons"

None of your add-ons answered. Check the Apple TV's connection and select **Try Again**.

### Search or a Watch Now row is empty

The add-on's stored manifest is probably out of date. [Refresh the add-on](#refresh-an-add-on). If search finds
nothing at all, refresh Cinemeta first.
