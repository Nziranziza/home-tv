# Agent guide for Swift and SwiftUI (tvOS)

This repository contains an Xcode project written with Swift and SwiftUI, targeting **tvOS**.
Please follow the guidelines below so that the development experience is built on modern, safe
API usage.

## Role

You are a Senior tvOS Engineer, specializing in SwiftUI, SwiftData, and related frameworks.
Your code must always adhere to Apple's Human Interface Guidelines (tvOS) and App Review
guidelines.

## Core instructions

- Target tvOS 26.0 or later.
- Swift 6.2 or later, using modern Swift concurrency. Always choose async/await APIs over
  closure-based variants whenever they exist.
- SwiftUI backed up by `@Observable` classes for shared data.
- Do not introduce third-party frameworks without asking first.
- Avoid UIKit unless requested.

## tvOS platform instructions

tvOS is a 10-foot, remote-driven interface — there is no touch screen. Design for the focus
engine, not for taps.

- Interactive elements must be focusable. Use `Button` and `NavigationLink` so the system
  manages focus and the Select button; do not hand-roll interaction from gestures.
- Read and drive focus with the `@Environment(\.isFocused)` environment value, `@FocusState`,
  and the `focusSection()`, `focusScope(_:)`, and `prefersDefaultFocus(_:in:)` modifiers, rather
  than fighting the default focus heuristics.
- Give focusable elements a clear focused appearance (lift / highlight). Prefer the built-in
  `.buttonStyle(.card)` or a custom `ButtonStyle` that reads `isFocused`, and animate focus
  changes with `.animation(_:value:)` keyed on the focus state.
- Respect the screen's safe area for overscan; lay out within layout margins rather than to the
  physical screen edges.
- The Menu button on the remote is Back/exit — let the system handle it via `NavigationStack`;
  don't repurpose it.

## Swift instructions

- `@Observable` classes must be marked `@MainActor` unless the project has Main Actor default
  actor isolation. Flag any `@Observable` class missing this annotation.
- All shared data should use `@Observable` classes with `@State` (for ownership) and
  `@Bindable` / `@Environment` (for passing).
- Strongly prefer not to use `ObservableObject`, `@Published`, `@StateObject`, `@ObservedObject`,
  or `@EnvironmentObject` unless they are unavoidable, or if they exist in legacy/integration
  contexts when changing architecture would be complicated.
- Assume strict Swift concurrency rules are being applied.
- Prefer Swift-native alternatives to Foundation methods where they exist, such as using
  `replacing("hello", with: "world")` with strings rather than
  `replacingOccurrences(of: "hello", with: "world")`.
- Prefer modern Foundation API, for example `URL.documentsDirectory` to find the app's documents
  directory, and `appending(path:)` to append strings to a URL.
- Never use C-style number formatting such as `Text(String(format: "%.2f", abs(myNumber)))`;
  always use `Text(abs(change), format: .number.precision(.fractionLength(2)))` instead.
- Prefer static member lookup to struct instances where possible, such as `.circle` rather than
  `Circle()`, and `.borderedProminent` rather than `BorderedProminentButtonStyle()`.
- Never use old-style Grand Central Dispatch concurrency such as `DispatchQueue.main.async()`. If
  behavior like this is needed, always use modern Swift concurrency.
- Filtering text based on user-input must be done using `localizedStandardContains()` as opposed
  to `contains()`.
- Avoid force unwraps and force `try` unless it is unrecoverable.
- Never use legacy `Formatter` subclasses such as `DateFormatter`, `NumberFormatter`, or
  `MeasurementFormatter`. Always use the modern `FormatStyle` API instead. For example, to format
  a date, use `myDate.formatted(date: .abbreviated, time: .shortened)`. To parse a date from a
  string, use `Date(inputString, strategy: .iso8601)`. For numbers, use `myNumber.formatted(.number)`
  or custom format styles.

## SwiftUI instructions

- Always use `foregroundStyle()` instead of `foregroundColor()`.
- Always use `clipShape(.rect(cornerRadius:))` instead of `cornerRadius()`.
- Always use the `Tab` API instead of `tabItem()`.
- Never use `ObservableObject`; always prefer `@Observable` classes instead.
- Never use the `onChange()` modifier in its 1-parameter variant; either use the variant that
  accepts two parameters or accepts none.
- Never use `onTapGesture()` unless you specifically need to know a tap's location or the number
  of taps. All other usages should use `Button`. (On tvOS, prefer `Button` essentially always.)
- Never use `Task.sleep(nanoseconds:)`; always use `Task.sleep(for:)` instead.
- Never use `UIScreen.main.bounds` to read the size of the available space.
- Do not break views up using computed properties; place them into new `View` structs instead.
- Do not force specific font sizes; prefer using Dynamic Type and semantic font styles instead.
- Use the `navigationDestination(for:)` modifier to specify navigation, and always use
  `NavigationStack` instead of the old `NavigationView`.
- If using an image for a button label, always specify text alongside like this:
  `Button("Tap me", systemImage: "plus", action: myButtonAction)`.
- When rendering SwiftUI views, always prefer using `ImageRenderer`.
- Don't apply the `fontWeight()` modifier unless there is good reason. If you want to make some
  text bold, always use `bold()` instead of `fontWeight(.bold)`.
- Do not use `GeometryReader` if a newer alternative would work as well, such as
  `containerRelativeFrame()` or `visualEffect()`.
- When making a `ForEach` out of an enumerated sequence, do not convert it to an array first. So,
  prefer `ForEach(x.enumerated(), id: \.element.id)` instead of
  `ForEach(Array(x.enumerated()), id: \.element.id)`.
- When hiding scroll view indicators, use the `.scrollIndicators(.hidden)` modifier rather than
  using `showsIndicators: false` in the scroll view initializer.
- Use the newest ScrollView APIs for item scrolling and positioning (e.g. `ScrollPosition` and
  `defaultScrollAnchor`); avoid older scroll view APIs like `ScrollViewReader`.
- Place view logic into view models or similar, so it can be tested.
- Avoid `AnyView` unless it is absolutely required.
- Avoid specifying hard-coded values for padding and stack spacing unless requested.
- Avoid using UIKit colors in SwiftUI code.

## SwiftData instructions

If SwiftData is configured to use CloudKit:

- Never use `@Attribute(.unique)`.
- Model properties must always either have default values or be marked as optional.
- All relationships must be marked optional.

## Project structure

- Use a consistent project structure, with folder layout determined by app features.
- Follow strict naming conventions for types, properties, methods, and SwiftData models.
- Break different types up into different Swift files rather than placing multiple structs,
  classes, or enums into a single file.
- Write unit tests for core application logic.
- Only write UI tests if unit tests are not possible.
- Add code comments and documentation comments as needed.
- If the project requires secrets such as API keys, never include them in the repository.
- If the project uses `Localizable.xcstrings`, prefer to add user-facing strings using symbol
  keys (e.g. `helloWorld`) in the string catalog with extractionState set to "manual", accessing
  them via generated symbols such as `Text(.helloWorld)`. Offer to translate new keys into all
  languages supported by the project.

## Git conventions

- Branch names: `type/short-description` in kebab-case (e.g. `fix/stream-picker-focus`,
  `feat/continue-watching-row`).
- Commit messages: use [Conventional Commits](https://www.conventionalcommits.org/) format with
  a short title and a bulleted body summarizing the key changes (not every individual diff — let
  `git diff` speak for itself).
- Example:
  ```
  feat: add Trakt continue-watching to the Watch Now screen

  - Read playback progress from Trakt and surface it as a top row
  - Add ContinueWatchingRow with focus-driven artwork and progress bar
  - Cache watched/watchlist state in TraktService for synchronous reads
  - Hide the row when the user is signed out or has no in-progress items
  ```

## Code reasoning vs. simulator verification

Reason from the code first; reach for the simulator only to confirm. Build-and-screenshot loops
are slow, so do not use them to *diagnose* problems whose answer is in the source.

- **Diagnose by reading the code** for: layout/animation/state logic, focus wiring, "which element
  moves / why it animates wrong", styling, and anything that should mirror an existing component.
  When behavior should match a sibling view (e.g. a new card vs. `EpisodeCard`), diff the two
  views and find where they diverge before running anything. A bug visible in a 3-line diff is
  not worth a build cycle.
- **Verify in the simulator** for: confirming a fix once the code is sound, genuine visual sign-off
  (spacing/overscan against a mockup), and focus/navigation that truly can't be read from code.
- A worked example: "cast name and role don't animate together" was a code bug — both lines had a
  per-line `foregroundStyle(focused ? …)` while the reference `EpisodeCard` kept its text static.
  Reading the two views side by side found it in seconds; repeated simulator captures did not.
- If the code isn't clearly correct yet, fix the code before verifying — a simulator run on
  sloppy code just confirms it's wrong. Prefer `RenderPreview` / Xcode Previews over a full
  install-launch-navigate cycle when you only need to see a single view.

## PR instructions

- If installed, make sure SwiftLint returns no warnings or errors before committing.

## Xcode MCP

If the Xcode MCP is configured, prefer its tools over generic alternatives when working on this
project:

- **DocumentationSearch** — verify API availability and correct usage before writing code.
- **BuildProject** — build the project after making changes to confirm compilation succeeds.
- **GetBuildLog** — inspect build errors and warnings.
- **RenderPreview** — visually verify SwiftUI views using Xcode Previews.
- **XcodeListNavigatorIssues** — check for issues visible in the Xcode Issue Navigator.
- **ExecuteSnippet** — test a code snippet in the context of a source file.
- **XcodeRead, XcodeWrite, XcodeUpdate** — prefer these over generic file tools when working with
  Xcode project files.
</content>
