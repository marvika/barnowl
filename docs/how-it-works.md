# How Barkeep works

Barkeep is a Swift app (AppKit plus SwiftUI) for macOS 26. It isn't sandboxed
and can't be on the App Store: reading other apps' menu bar items needs
Accessibility, and the macOS 27 engine uses a private API.

## Project layout

| Folder | What's there |
|---|---|
| `Barkeep/App` | App delegate, the shared `AppModel`, `barkeep://` link handling |
| `Barkeep/MenuBar` | Status items, sections, hiding engines, item scanning, moving and opening icons |
| `Barkeep/Layout` | The layout editor and `LayoutController`, which remembers and restores icon positions |
| `Barkeep/Groups` | Groups and custom icons |
| `Barkeep/Context` | Show when it changes, presenter mode |
| `Barkeep/KeepAwake` | Sessions, rules, closed-lid mode |
| `Barkeep/Clipboard` | Clipboard history, shelf and drop tray |
| `Barkeep/Search`, `QuickPanel`, `BarkeepBar`, `Settings`, `Onboarding`, `Appearance` | The panels and windows |
| `Barkeep/Automation` | Shortcuts actions |
| `BarkeepTests` | Unit tests for the logic that doesn't need a real menu bar |
| `Scripts` | `install.sh`, `demo.sh`, the `barkeep` command, icon and hero image generators |

The Xcode project is generated from `project.yml` with XcodeGen.

## Hiding

Barkeep owns three status items: the **arrow**, a `|` **divider**, and an
optional `⋮` **always-hidden divider**.

- **macOS 26** (`LengthEngine`): to hide, the divider's width grows to about
  the screen's width, which pushes everything left of it past the left edge.
  This needs no permissions. On first launch Barkeep seeds
  `NSStatusItem Preferred Position` so the arrow sits next to Control Center,
  never behind the notch.
- **macOS 27** (`NativeVisibilityEngine`, untested): macOS drops over-wide
  status items, so Barkeep reads which apps sit left of the divider and asks
  macOS to show only the others, through `MenuBarClientCore`'s
  assessment-mode restriction (found by Hidden Bar). Hiding is per app there,
  and system items always stay.

Both sit behind the `HidingEngine` protocol, so a future macOS only needs a
new engine.

## Finding icons

On macOS 26 every menu bar item's window belongs to Control Center, so the
window list can't say which app an icon belongs to. `ItemScanner` reads each
app's `AXExtrasMenuBar` items through Accessibility, and matches them to the
status windows by horizontal position, within 4 pt. Barkeep's own windows are
left out of the matching. Each icon gets a **key** (bundle ID plus the status
item's autosave name, such as `com.example.app/Item-0`), which survives
relaunches. Layouts and groups are stored by key.

Sections are worked out from the dividers' real frames, even when a divider
is off screen.

## Pictures

macOS 26 can't capture off-screen windows: ScreenCaptureKit refuses with
error -3811, and the old `CGWindowListCreateImage` calls return nothing. Icons
behind the notch count as off screen too. So `ItemImageCache` takes one
ScreenCaptureKit picture of the menu bar strip whenever icons are showing, at
launch and when you reveal them. That picture includes only the status
windows, so its background is transparent. Barkeep crops it into one picture
per icon and saves them to `~/Library/Application Support/Barkeep/Icons`.
**Refresh Pictures** briefly moves icons that have no picture into view.

## Moving icons

`ItemMover` moves any icon with a synthetic ⌘-drag, the way Frost does:

1. A ⌘ mouse-down is posted **on Barkeep's own arrow**, with event field
   `0x33` set to the target icon's window ID. macOS routes the event by that
   field and lifts the target icon, even an off-screen one.
2. Barkeep waits until the icon has lifted (20–60 ms).
3. It posts the mouse-up next to the destination, then checks the result and
   retries up to three times.

Another app's icon is never clicked. The pointer is hidden during the move
and put back afterwards. "Left of the arrow" is unreliable, because the
lifted icon's slot is reserved where the mouse-down lands. So Barkeep's
destinations are relative to the dividers, or right of a group or custom
icon.

## Opening a hidden icon

A hidden icon ignores presses, because its menu would open off screen.
`ItemOpener` moves it next to the icon you clicked, presses it through
Accessibility, and moves it back once its menu closes. Apps busy opening
their menu often answer the press with "cannot complete" even though it
worked, so Barkeep checks for a menu window before falling back to a real
click.

## Keeping icons in place

`LayoutKeeper` (pure, tested) compares each scan with the saved layout:

- a key with a **new window** in the wrong row means the app re-added its
  icon, so Barkeep moves it back;
- the **same window** in a new row means you moved it, so the new row is
  saved;
- a **new key** goes where "New icons go" says.

A `CorrectionLimiter` allows at most two corrections per icon in two minutes,
so a disagreement can never turn into a loop.

## Show when it changes

Every 3 seconds `ChangeWatcher` compares each watched icon's status text
(title, description and help from Accessibility), its width, and its window
ID. After a real network change (`NWPathMonitor`, debounced, at most once a
minute), or on an opt-in interval, it photographs watched icons. If an icon
is hidden, it's slid into view for the photo. It then compares a 12×12
grayscale thumbnail. A changed icon is moved next to the arrow and returned
later.

## Presenter mode

While the screen is shared or recorded, Control Center's own menu bar item
describes itself as "Control Center, Screen Recording is in use". Barkeep
reads that through Accessibility. Barkeep's own picture taking lights up the
same indicator, so it ignores the 10 seconds after its own captures and needs
two readings in a row. Presenting moves the visible icons into the hidden
section without changing the saved layout, and restores them in order
afterwards.

## Keep awake

`KeepAwakeController` holds one `IOPMAssertion`, the same mechanism as
`caffeinate` and Amphetamine. It's held while either a session or an active
rule wants it, and it's display-sleep or system-sleep depending on the
options. Rules are checked every 15 seconds and when apps, displays or power
change. Power and battery come from IOKit, the microphone from CoreAudio
(`kAudioDevicePropertyDeviceIsRunningSomewhere`, no permission needed), and
downloads from unfinished files in ~/Downloads. That last one is only read
when a rule or session uses it. Closed-lid mode runs
`pmset -a disablesleep 1` with an administrator prompt.

## Clipboard and drop tray

`ClipboardHistory` polls the pasteboard's change count twice a second. It
skips anything marked concealed or transient (nspasteboard.org) and copies
made in known password managers. The drop tray watches global mouse drags. A
drag that changes the drag pasteboard with file URLs is a file drag, so the
tray slides out under the notch.

## Demo mode

`Scripts/demo.sh` runs a copy of Barkeep with its own bundle ID and settings,
and with `BarkeepDemo` set. Demo mode shows made-up icons, clipboard entries
and shelf files, and never reads, moves or saves anything real. The
screenshots in this repository come from it.
