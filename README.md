# Barkeep

A tidier macOS menu bar, and a Mac that stays awake when you need it to.
Open source (MIT), for macOS 26 Tahoe and macOS 27.

- **Hide the clutter.** An arrow and a `|` divider split your menu bar. Icons
  left of the divider are hidden until you click the arrow, and hide again
  after a few seconds. An optional `⋮` divider adds an always-hidden section.
- **Barkeep Bar.** On a notched MacBook there's only room for a few icons.
  The Barkeep Bar shows hidden icons, and any stuck behind the notch, in a
  strip under the menu bar. Click one to open its menu. Choose Automatic, In
  the menu bar, or In the Barkeep Bar.
- **Search.** Press ⌃⌥⌘M and type to find and open any menu bar icon.
- **Keep awake.** For a set time, indefinitely, or while an app is running,
  with or without letting the display sleep. Replaces Amphetamine for the
  common cases.
- **Quick toggles.** Dark mode, desktop icons and Finder hidden files from the
  arrow's right-click menu.
- **Guided setup and a System Settings–style Settings window.**

## Using it

| Action | How |
|---|---|
| Show hidden icons | Click the arrow, or press ⌃⌥⌘B |
| Search the menu bar | ⌃⌥⌘M |
| Show every icon | Option-click the arrow |
| Menu (Keep Awake, toggles, Settings) | Right-click or control-click the arrow |
| Choose what's hidden | Hold ⌘ and drag icons across the `\|` divider |

### URL scheme

For Shortcuts, Raycast or scripts:

```
barkeep://toggle            barkeep://show-all          barkeep://hide
barkeep://bar               barkeep://search            barkeep://open?app=OneDrive
barkeep://keep-awake?minutes=60    barkeep://keep-awake/stop
barkeep://settings          barkeep://setup
```

## Building

Requires Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
open Barkeep.xcodeproj
```

Builds are ad-hoc signed by default. macOS ties Accessibility permission to
the signature, so an ad-hoc build loses it on every rebuild. To keep it, copy
`Config/Local.xcconfig.example` to `Config/Local.xcconfig` (git-ignored) and
set your team ID.

Run the tests with:

```bash
xcodebuild -project Barkeep.xcodeproj -scheme Barkeep test
```

## Permissions

- **Accessibility** lets Barkeep list menu bar icons and open them from the
  Barkeep Bar and search.
- **Screen Recording** lets the Barkeep Bar show real pictures of hidden icons
  instead of app icons. macOS applies it after Barkeep relaunches.

Hiding itself needs neither on macOS 26.

## How it works

Barkeep isn't sandboxed and can't be on the App Store: reading other apps'
menu bar items needs Accessibility, and macOS 27 hiding uses a private API.

- **macOS 26:** the `|` divider is a status item whose width grows to about
  the screen width, pushing everything to its left off screen
  (`LengthEngine`). Needs no permissions. On first launch Barkeep seeds
  `NSStatusItem Preferred Position` so its arrow sits next to Control Center,
  not behind the notch.
- **macOS 27:** the system drops over-wide status items, so Barkeep reads
  which apps sit left of the divider through Accessibility and asks macOS to
  show only the rest, through MenuBarClientCore's assessment-mode restriction
  (`NativeVisibilityEngine`). Hiding is per app there, and system items always
  stay. **Not yet tested on macOS 27.**
- **Finding items:** on macOS 26 every menu bar item window belongs to
  Control Center, so Barkeep reads each app's `AXExtrasMenuBar` items and
  matches them to windows by position (`ItemScanner`).
- **Pictures:** macOS 26 won't capture off-screen windows (ScreenCaptureKit
  fails, and the old CGWindowList calls return nothing), so Barkeep takes one
  ScreenCaptureKit shot of the menu bar strip whenever icons are showing and
  keeps the crops (`ItemImageCache`).
- **Opening a hidden item:** a hidden item ignores presses, so Barkeep reveals
  its section, presses it through Accessibility (falling back to a real
  click), and hides again once its menu closes (`ItemOpener`).
- **Keep awake** holds an `IOPMAssertion`, like `caffeinate` and Amphetamine.

Both engines sit behind the `HidingEngine` protocol, so a future macOS only
needs a new engine. See [docs/ROADMAP.md](docs/ROADMAP.md) for what's next.

## Prior art

Barkeep learned from [Hidden Bar](https://github.com/dwarvesf/hidden) and
[Frost](https://github.com/frostbar/frost) (both MIT; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)), and from reading
[Ice](https://github.com/jordanbaird/Ice) and
[Thaw](https://github.com/thaw-app/Thaw) (GPL-3; no code copied).
