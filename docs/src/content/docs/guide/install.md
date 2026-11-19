---
title: Install HomeTV
description: Build HomeTV in Xcode and install it on your Apple TV.
---

HomeTV isn't on the App Store. You install it by building it on a Mac with Xcode and sending it to your Apple TV
over your home network. This is called sideloading. It takes about half an hour the first time and a few minutes
after that.

## What you need

- **A Mac** with [Xcode](https://apps.apple.com/app/xcode/id497799835) 26.3 or later, from the Mac App Store.
- **An Apple TV** (HD or 4K) running tvOS 26 or later, on the same network as the Mac.
- **An Apple Account.** A free one works, but the app then stops opening after 7 days and has to be installed again.
  A paid [Apple Developer Program](https://developer.apple.com/programs/) membership ($99 a year) makes it last a
  year. See [Keep HomeTV running](#keep-hometv-running).
- **[Homebrew](https://brew.sh)**, to install XcodeGen, the tool that creates the Xcode project.

## 1. Set up Xcode

1. Open Xcode once and let it install its components.
2. Add the Apple TV platform. Open **Xcode → Settings → Components** and click **Get** next to tvOS. You can also
   run this in Terminal:

   ```sh
   xcodebuild -downloadPlatform tvOS
   ```

3. Sign in with your Apple Account. Open **Xcode → Settings → Accounts**, click **+**, choose **Apple Account** and
   sign in. With a free account Xcode lists a team named after you with **(Personal Team)** after it.
4. Create a signing certificate. In the same window, select your team, click **Manage Certificates…**, click **+**
   and choose **Apple Development**. Close the window.

## 2. Pair the Apple TV with Xcode

1. On the Apple TV, open **Settings → Remotes and Devices → Remote App and Devices**. Leave that screen open.
2. On the Mac, open **Xcode → Window → Devices and Simulators** and select the **Devices** tab.
3. The Apple TV appears in the sidebar under **Discovered**. Select it and click **Pair**.
4. A code appears on the TV. Type it into Xcode.

When pairing finishes, the Apple TV moves up to the connected devices. Xcode may spend a few minutes preparing it
for development. Wait until the progress message in the Devices window goes away.

## 3. Get the code

Open Terminal and run:

```sh
brew install xcodegen
git clone https://github.com/Nziranziza/home-tv.git
cd home-tv
cp Secrets.example.xcconfig Secrets.xcconfig
```

Run the rest of the commands on this page from the `home-tv` folder.

## 4. Set your signing team

Apple needs to know which team signs the app. Find your team ID, a 10-character code such as `A1B2C3D4E5`:

- **Paid account:** it's on the [Membership details](https://developer.apple.com/account#MembershipDetailsCard)
  page.
- **Free account:** run this in Terminal. The team ID is the `OU=` value.

  ```sh
  security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject
  ```

Open `Secrets.xcconfig` in a text editor and put the ID after `DEVELOPMENT_TEAM =`:

```
DEVELOPMENT_TEAM = A1B2C3D4E5
```

The same file holds optional keys for TMDB and Trakt. HomeTV installs and runs without them. They're covered in
[Setup and add-ons](/guide/setup-and-addons/).

## 5. Give the app your own identifiers

Every app on an Apple TV has a bundle identifier, and no two teams can use the same one. HomeTV's are taken by its
author, so replace them with your own. The app and its Top Shelf extension also share data through an App Group,
whose ID has to be unique too.

All of them contain `com.hometv`. Replace it with `com.` followed by a name of your own, using only letters, numbers
and hyphens. This command uses `com.yourname`. Change `yourname` before you run it:

```sh
sed -i '' 's/com\.hometv/com.yourname/g' \
  project.yml \
  HomeTV/HomeTV.entitlements \
  HomeTVTopShelf/HomeTVTopShelf.entitlements \
  HomeTV/Services/Shared/TopShelfSharedState.swift
```

This changes:

| Identifier | Becomes |
| --- | --- |
| App bundle ID | `com.yourname.HomeTV` |
| Top Shelf extension bundle ID | `com.yourname.HomeTV.TopShelf` |
| App Group | `group.com.yourname.HomeTVs` |

The App Group must be the same in all four files, or the Top Shelf can't read what the app shares with it. The
command changes them together.

## 6. Download the player

HomeTV's built-in player uses prebuilt video frameworks that aren't stored in the repository. Download them:

```sh
scripts/fetch-player-frameworks.sh
```

They go into `Vendor/PlayerFrameworks`. Run the script again if a later update changes the versions it pins.

## 7. Generate the Xcode project

```sh
xcodegen generate
open HomeTV.xcodeproj
```

Run `xcodegen generate` again whenever you change `project.yml` or `Secrets.xcconfig`.

## 8. Build and run

1. In Xcode's toolbar, make sure the scheme is **HomeTV**.
2. Click the run destination next to it and pick your Apple TV.
3. Press **⌘R**, or click the Run button.

The first build takes several minutes. If macOS asks whether `codesign` may use a key in your keychain, enter your
Mac password and click **Always Allow**, or it asks again for each player framework.

When the build finishes, HomeTV opens on the Apple TV. Continue with [Setup and add-ons](/guide/setup-and-addons/).

## Keep HomeTV running

With a free account, Apple's signature on the app lasts 7 days. After that HomeTV won't open. Rebuild it to
renew it:

1. Make sure the Apple TV is on and on the same network as the Mac.
2. Open `HomeTV.xcodeproj`, pick the Apple TV and press **⌘R**.

Your add-ons, library and settings stay on the Apple TV. A paid account signs the app for a year.

### Updating to a newer version

Your identifier changes from [step 5](#5-give-the-app-your-own-identifiers) are local edits to files in the
repository. Set them aside, pull the update and put them back:

```sh
git stash
git pull
git stash pop
scripts/fetch-player-frameworks.sh
xcodegen generate
```

Then build and run again.

## Troubleshooting

### The Apple TV doesn't appear in Xcode

- Check that the Mac and the Apple TV are on the same network, and that the network doesn't isolate devices from
  each other (guest networks often do).
- Keep **Remote App and Devices** open on the Apple TV while Xcode looks for it.
- Turn off a VPN on the Mac.
- Restart the Apple TV (**Settings → System → Restart**) and quit and reopen Xcode.
- If it was paired before and stopped connecting, right-click it in **Devices and Simulators**, choose
  **Unpair Device** and pair again.

### The Apple TV is grey or unavailable as a run destination

Xcode is still preparing the Apple TV, or its tvOS is newer than your Xcode supports. Wait for the Devices window to
finish, and update Xcode if the Apple TV was just updated.

### "Signing for HomeTV requires a development team"

`DEVELOPMENT_TEAM` is empty or wrong. Check `Secrets.xcconfig`, then run `xcodegen generate` and build again.

### "Failed to register bundle identifier" or "The app identifier … cannot be registered to your development team"

Another team owns that identifier. Pick a different name in
[step 5](#5-give-the-app-your-own-identifiers). If you already ran the command once, the files now contain your
first name rather than `com.hometv`, so replace that instead. Then run `xcodegen generate`.

### "No profiles for 'com.yourname.HomeTV' were found"

Xcode couldn't make a provisioning profile. Select the **HomeTV** project in Xcode's sidebar, open the **HomeTV**
target's **Signing & Capabilities** tab and read the error there. Usually the fix is one of the two above.

With a free account, Apple also limits how many new identifiers you can register: 10 a week. Each install uses two
(the app and the Top Shelf). If you've hit the limit, wait a few days or reuse a name you've already registered.

### "Player frameworks missing. Run scripts/fetch-player-frameworks.sh, then rebuild."

The player frameworks aren't in `Vendor/PlayerFrameworks`, or a download didn't finish. Run
`scripts/fetch-player-frameworks.sh`, wait for "Player frameworks ready", and build again.

### "Could not launch HomeTV" or the app closes straight away

The signature has expired. Rebuild as in [Keep HomeTV running](#keep-hometv-running). If the Apple TV was asleep,
wake it and run again.
