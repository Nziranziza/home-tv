---
title: Contributing
description: How to branch, commit, write code, test and document a change to HomeTV.
---

This page covers what a reviewer checks on a pull request. Set up a checkout first with
[Build from source](/developers/build-from-source/). The full rule list lives in
[`CLAUDE.md`](https://github.com/Nziranziza/home-tv/blob/main/CLAUDE.md), which coding agents read too. This page is
the short version for people.

## Before you start

- Look for an [issue](https://github.com/Nziranziza/home-tv/issues) that covers the change, or open one, and mention
  it in the pull request.
- Ask in the issue before adding a third-party framework or Swift package.
- Never commit secrets. API keys go in `Secrets.xcconfig`, which is gitignored.

## Branches

Name branches `type/short-description` in kebab-case, using the same types as commit messages:

```text
feat/continue-watching-row
fix/stream-picker-focus
docs/contributing-guide
```

## Commits

Write commit messages in [Conventional Commits](https://www.conventionalcommits.org/) format: a short title, a blank
line, then a bulleted body that sums up the main changes. Leave the line-by-line detail to the diff.

```text
feat: add Trakt continue-watching to the Watch Now screen

- Read playback progress from Trakt and surface it as a top row
- Add ContinueWatchingRow with focus-driven artwork and progress bar
- Cache watched/watchlist state in TraktService for synchronous reads
- Hide the row when the user is signed out or has no in-progress items
```

- Don't use double quotes (`"`) anywhere in the message. Write identifiers, labels and UI text without quotes.
- A pull request lands as **one commit**. Its body describes the finished change as a whole, not the order you built
  it in.
- Fold review fixes and follow-ups into that commit instead of adding new ones, then force-push the branch:

  ```sh
  git commit --amend          # or: git rebase -i main, then squash
  git push --force-with-lease
  ```

## SwiftLint

If [SwiftLint](https://github.com/realm/SwiftLint) is installed, run it from the repository root before you commit.
It must report no warnings and no errors.

```sh
brew install swiftlint
swiftlint
```

`.swiftlint.yml` excludes `docs/`.

## Swift and SwiftUI

The app targets **tvOS 26** and builds with **complete strict concurrency checking**. The rules reviewers flag most:

- **Shared state** lives in `@Observable` classes marked `@MainActor`, owned with `@State` and passed with
  `@Bindable` or `@Environment`. Don't use `ObservableObject`, `@Published`, `@StateObject` or `@EnvironmentObject`.
- **Concurrency** uses async/await. No `DispatchQueue`, and `Task.sleep(for:)` rather than
  `Task.sleep(nanoseconds:)`.
- **Formatting** uses `FormatStyle`, for example `date.formatted(date: .abbreviated, time: .shortened)`. No
  `DateFormatter`, `NumberFormatter` or `String(format:)`.
- **Text filtering** of user input uses `localizedStandardContains()`.
- **Views** are split into separate `View` structs, not computed properties. Logic goes in a model so it can be
  tested.
- **Modern modifiers**: `foregroundStyle()`, `clipShape(.rect(cornerRadius:))`, the `Tab` API,
  `NavigationStack` with `navigationDestination(for:)`, the two-parameter or zero-parameter `onChange`, and
  `.scrollIndicators(.hidden)`.
- **Layout** uses semantic fonts and the default padding and spacing, not fixed sizes. Prefer
  `containerRelativeFrame()` or `visualEffect()` over `GeometryReader`.
- **No UIKit** unless there's no SwiftUI way to do it, and no force unwraps or `try!` unless the failure can't be
  recovered from.
- **One type per file**, in the feature folder it belongs to. See [Architecture](/developers/architecture/) for the
  layout.

## tvOS focus

There's no touch screen. Everything is driven by the remote through the focus engine.

- **Make controls focusable.** Use `Button` and `NavigationLink` so the system handles focus and the Select button.
  Don't build interaction from `onTapGesture` or other gestures.
- **Show focus clearly.** Use `.buttonStyle(.card)` for artwork, or a custom `ButtonStyle` that reads
  `@Environment(\.isFocused)`. Animate the change with `.animation(_:value:)` keyed on focus.
- **Group focus into sections.** Put `focusSection()` on each row so a Down press lands in the row below, not on
  whatever is nearest. Steer focus with `@FocusState`, `focusScope(_:)` and `prefersDefaultFocus(_:in:)` rather than
  working against the default behaviour.
- **Respect overscan.** Lay content out inside the safe area and layout margins, never against the screen edges.
- **Leave the Menu button alone.** It means Back. `NavigationStack` handles it.

Check focus changes with the remote in the simulator or on an Apple TV, not only by reading the code.

## Tests

The **HomeTV** scheme runs both test targets. See [Build from source](/developers/build-from-source/#tests) for the
command.

- **`HomeTVTests`** holds unit tests, written with [Swift Testing](https://developer.apple.com/documentation/testing)
  (`@Test`, `#expect`). Add one for new logic: ranking, queueing, parsing, player state and so on. Shared fixtures
  such as `Fixture.meta(…)`, `FakePlaybackEngine` and `StubThumbnailer` are in the same folder.
- **`HomeTVUITests`** holds UI tests, written with XCTest and `XCUIRemote`. Write one only when a unit test can't
  cover the behaviour, which usually means a focus or directional-press bug. Launch the app with a mock fixture such
  as `MOCK_HERO` or `MOCK_STREAMS` so the test doesn't depend on a live catalog. The fixtures are listed under
  [Debug launch environment variables](/developers/build-from-source/#test-data).

A pull request should build and pass both targets.

## Documentation

Update the docs in the same pull request as the change, whenever users or developers would notice it.

- Pages are Markdown files in `docs/src/content/docs/`. A new page also needs an entry in the sidebar in
  `docs/astro.config.mjs`.
- Describe how the app works now. Don't write change history or *new in* notes.
- Screenshots go in `docs/src/assets/screenshots/`, taken from the tvOS Simulator at 1920×1080 with
  `xcrun simctl io booted screenshot`. Commit only the final images.
- Preview the site locally:

  ```sh
  cd docs
  npm install
  npm run dev    # http://localhost:4321
  ```

Each pull request that touches `docs/` gets a preview link from Cloudflare.

## Pull request checklist

- [ ] The branch is named `type/short-description`.
- [ ] The pull request is one Conventional Commit with no double quotes.
- [ ] SwiftLint reports nothing, if installed.
- [ ] The app builds, and both test targets pass.
- [ ] New logic has unit tests.
- [ ] Every new control can be reached and used with the remote, and shows focus.
- [ ] The docs describe the change.
