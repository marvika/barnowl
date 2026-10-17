# Barkeep

A tidier macOS menu bar, and a Mac that stays awake when you need it to.
Open source (MIT), for macOS 26 Tahoe and macOS 27.

- **Hide the clutter.** An arrow and a `|` divider split your menu bar. Icons
  left of the divider are hidden until you click the arrow. An optional `⋮`
  divider adds an always-hidden section.
- **Arrange without fiddling.** Settings → Layout shows every icon with its
  real picture. Drag icons between Menu bar, Hidden, Always hidden and your
  groups, and Barkeep moves the real icons. Right-click any icon for "Always
  Show in Menu Bar", "Hide" and more.
- **Groups.** A group is one icon in the menu bar, for example a briefcase for
  "Work", that opens a strip with its icons.
- **Icons stay put.** Barkeep remembers where each icon belongs and puts it
  back when an app relaunches. New icons go to Hidden (or the menu bar, if
  you prefer).
- **Show on change.** Right-click an icon and choose "Show When It Changes":
  when its status changes (OneDrive starts syncing, a VPN drops), it shows
  next to the arrow for a while, then hides again.
- **Presenter mode.** Starts by itself when you share or record your screen
  (or from the quick panel or a shortcut): every other app's icon goes out of
  sight, the Mac stays awake, and everything comes back afterwards. Optional:
  hide desktop icons too.
- **A layout for your desk.** Optionally keep one layout for the laptop screen
  and another while an external display is connected; Barkeep switches when
  you dock.
- **Barkeep Bar.** On a notched MacBook there's only room for a few icons.
  The Barkeep Bar shows hidden icons, and any stuck behind the notch, in a
  strip under the menu bar. Click one and its menu opens right there.
- **Search and commands.** Press ⌃⌥⌘M and type to find and open any menu bar
  icon, or type a command: "awake 2h", "dark", "present", "mute", "arrange".
- **Custom icons.** Right-click an icon and choose "Replace Icon…" to show a
  symbol, text or emoji instead (say "VPN" for Zscaler); it opens the real
  icon's menu.
- **Clipboard history and shelf.** ⌃⌥⌘V shows what you copied; Return pastes
  it into the app you were using. Password-manager copies are never recorded.
  The shelf holds files you drop on it until you drag them out.
- **Appearance.** Optional menu bar tint (off by default; full width, rounded
  or split around the notch) and icon spacing, so more icons fit beside the
  notch.
- **Hover or scroll to reveal** hidden icons (optional).
- **Keep awake.** Everything most people use Amphetamine for: for a set time,
  until a time, while an app runs, until downloads finish, or by rules (on
  power with an external display, during calls, on a schedule…). Stops below
  a battery level, can keep Teams and Slack from showing you as Away, and has
  an optional closed-lid mode.
- **Quick panel.** Click the cup icon for keep awake and toggles: dark mode,
  microphone mute, hide desktop icons, hidden files, sleep display.
- **Guided setup and a System Settings–style Settings window.**

## Using it

| Action | How |
|---|---|
| Show hidden icons | Click the arrow, or press ⌃⌥⌘B |
| Search the menu bar | ⌃⌥⌘M |
| Show every icon | Option-click the arrow |
| Keep awake and toggles | Click the cup, or right-click the arrow |
| Start or stop keep awake | Option-click the cup |
| Arrange icons and groups | Settings → Layout, or ⌘-drag in the menu bar |
| Clipboard history | ⌃⌥⌘V |

### Shortcuts, Terminal and links

Barkeep adds Shortcuts actions: Keep Mac Awake, Stop Keeping Mac Awake, Set
Presenter Mode, Show or Hide Menu Bar Icons, Open Menu Bar Icon and Show
Clipboard History.

`Scripts/install.sh` also installs a `barkeep` command:

```
barkeep awake 90          barkeep awake stop        barkeep present on
barkeep open zscaler      barkeep place zscaler hidden
barkeep icon zscaler VPN  barkeep watch onedrive    barkeep clipboard
```

Everything is also available as `barkeep://` links (`barkeep://keep-awake?minutes=60`,
`barkeep://open?app=OneDrive`, `barkeep://settings?pane=layout`…), for Raycast
and the like.

## Installing

```bash
brew install xcodegen
Scripts/install.sh
```

This builds a Release copy, installs it in /Applications, puts the `barkeep`
command on your PATH and starts Barkeep. Run it again to update.

Barkeep isn't notarized (that needs a paid Developer ID certificate), so
it's meant to be built on the Mac that runs it.

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
- **Moving icons:** a synthetic ⌘-drag whose mouse-down lands on Barkeep's own
  arrow and is routed to the target icon by event field `0x33`, so even
  off-screen icons can be moved and no other app's icon is ever clicked
  (`ItemMover`, Frost's technique).
- **Opening a hidden item:** a hidden item ignores presses, so Barkeep moves it
  next to the icon you clicked, presses it through Accessibility (falling back
  to a real click), and moves it back once its menu closes (`ItemOpener`).
- **Show on change:** macOS can't photograph hidden icons, so Barkeep watches
  what it can read (status text, width, the app re-adding the icon) every few
  seconds, and after a network change (or every few minutes, if you opt in)
  slides watched icons into view for a moment to compare their pictures.
- **Presenter mode** spots screen sharing from Control Center's own
  "Screen Recording is in use" description, and ignores the few seconds after
  Barkeep's own icon pictures, which light up the same indicator.
- **Pictures** are kept in `~/Library/Application Support/Barkeep/Icons`, so
  they survive relaunches.
- **Keep awake** holds an `IOPMAssertion`, like `caffeinate` and Amphetamine.

Both engines sit behind the `HidingEngine` protocol, so a future macOS only
needs a new engine. See [docs/ROADMAP.md](docs/ROADMAP.md) for what's next.

## Prior art

Barkeep learned from [Hidden Bar](https://github.com/dwarvesf/hidden) and
[Frost](https://github.com/frostbar/frost) (both MIT; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)), and from reading
[Ice](https://github.com/jordanbaird/Ice) and
[Thaw](https://github.com/thaw-app/Thaw) (GPL-3; no code copied).
