# Barkeep

A tidier macOS menu bar, and a Mac that stays awake when you need it to.
Open source (MIT), for macOS 26 Tahoe and macOS 27.

- **Hide the clutter.** An arrow and a `|` divider split your menu bar. Icons
  left of the divider are hidden until you click the arrow, and hide again
  after a few seconds. An optional `⋮` divider adds an always-hidden section.
- **Keep awake.** For a set time, indefinitely, or while an app is running,
  with or without letting the display sleep. Replaces Amphetamine for the
  common cases.
- **Quick toggles.** Dark mode, desktop icons and Finder hidden files from the
  arrow's right-click menu.
- **Guided setup and a System Settings–style Settings window.**

## Using it

| Action | How |
|---|---|
| Show or hide icons | Click the arrow, or press ⌃⌥⌘B |
| Show every icon | Option-click the arrow |
| Menu (Keep Awake, toggles, Settings) | Right-click or control-click the arrow |
| Choose what's hidden | Hold ⌘ and drag icons across the `\|` divider |

### URL scheme

For Shortcuts, Raycast or scripts:

```
barkeep://toggle            barkeep://show-all          barkeep://hide
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
- **Keep awake** holds an `IOPMAssertion`, like `caffeinate` and Amphetamine.

Both engines sit behind the `HidingEngine` protocol, so a future macOS only
needs a new engine. See [docs/ROADMAP.md](docs/ROADMAP.md) for what's next.

## Prior art

Barkeep learned from [Hidden Bar](https://github.com/dwarvesf/hidden) and
[Frost](https://github.com/frostbar/frost) (both MIT; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)), and from reading
[Ice](https://github.com/jordanbaird/Ice) and
[Thaw](https://github.com/thaw-app/Thaw) (GPL-3; no code copied).
