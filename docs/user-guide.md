# Barkeep user guide

- [Getting started](#getting-started)
- [Hiding icons](#hiding-icons)
- [Arranging icons](#arranging-icons)
- [Groups and custom icons](#groups-and-custom-icons)
- [Show when it changes](#show-when-it-changes)
- [Presenter mode](#presenter-mode)
- [A separate layout at your desk](#a-separate-layout-at-your-desk)
- [Keep awake](#keep-awake)
- [Quick panel and toggles](#quick-panel-and-toggles)
- [Search and commands](#search-and-commands)
- [Clipboard history and the drop tray](#clipboard-history-and-the-drop-tray)
- [Appearance](#appearance)
- [Automation](#automation)
- [Troubleshooting](#troubleshooting)

## Getting started

When Barkeep opens for the first time, a short setup guide walks you through
it. You can run it again any time from Settings → General → Setup guide.

Barkeep asks for two permissions in **System Settings → Privacy & Security**:

| Permission | What it's for | Without it |
|---|---|---|
| Accessibility | Listing, moving and opening menu bar icons | Hiding still works; the Barkeep Bar, search, arranging and groups don't |
| Screen Recording | Real pictures of hidden icons | You see app icons instead of the real icons |

macOS applies Screen Recording only after Barkeep restarts. The setup guide
and Settings offer a **Relaunch Barkeep** button for that.

Turn on **Open at login** in Settings → General to keep your menu bar tidy
from the start.

## Hiding icons

Barkeep adds an **arrow** to your menu bar, next to Control Center, and a
`|` divider left of it. Icons left of the divider are hidden.

- **Click the arrow** or press **⌃⌥⌘B** to see your hidden icons. Click again
  to hide them.
- **Option-click the arrow** to show everything, including always-hidden
  icons.
- **Right-click the arrow** for the quick panel.

### Where hidden icons appear

Choose in Settings → Menu Bar:

- **In the Barkeep Bar:** a strip under the menu bar. Click an icon and
  Barkeep brings it next to the arrow and opens its menu, then puts it back.
- **In the menu bar:** hidden icons slide back into the menu bar itself.
- **Automatic** (the default): the menu bar when there's room, the Barkeep
  Bar when there isn't. On a notched MacBook that's usually the Barkeep Bar,
  because only a few icons fit beside the notch. Icons that end up behind
  the notch always show in the Barkeep Bar.

### Other options (Settings → Menu Bar)

- **Hide icons again automatically** after a few seconds (on by default).
  Barkeep waits while your pointer is in the menu bar.
- **Always-hidden section:** a second `⋮` divider. Icons left of it stay
  hidden until you option-click the arrow, search for them, or open them from
  a group.
- **Show hidden icons when hovering over the arrow**, or **scroll over the
  menu bar** (down shows, up hides). Both are off by default.
- **New icons go:** hidden (the default) or in the menu bar.

## Arranging icons

Open **Settings → Layout**, or click **Arrange** in the Barkeep Bar.

Every icon appears with its real picture in rows: **Menu bar**, **Hidden**,
**Always hidden**, and one row per group. Drag an icon to another row, or onto
another icon to put it right before that one. Barkeep moves the real icon
straight away.

Right-click an icon for:

- **Always Show in Menu Bar**, **Hide**, **Always Hide**
- **Move to Group**
- **Replace Icon…** (see below)
- **Show When It Changes** (see below)

The clock and Control Center have a lock: macOS doesn't let anyone move them.

You can still ⌘-drag icons in the menu bar itself, as with any Mac, and
Barkeep remembers that too.

**Refresh Pictures** in Layout fills in icons that show an app icon instead
of their real picture. Icons behind the notch or off screen can't be
photographed, so Barkeep briefly brings each one into view.

### Icons stay where you put them

Barkeep remembers which row each icon belongs to. When an app restarts and
macOS puts its icon somewhere else, Barkeep moves it back. If it can't keep
an icon in place after two tries, it stops trying, so your pointer is never
kept busy.

## Groups and custom icons

**Groups** gather several icons behind one. In Settings → Layout click
**New Group**, give it a name and an icon, then drag icons into its row. The
group's icon appears in the menu bar. Click it for a strip with its icons, or
right-click it to edit. The icons themselves wait in the always-hidden
section.

**Custom icons** replace one app's icon with a symbol, an emoji or a bit of
text. Right-click the icon in Layout or the Barkeep Bar and choose **Replace
Icon…**. Clicking your icon opens the app's menu directly. To go back,
delete the custom icon's group in Layout (Edit → Delete Group).

## Show when it changes

Right-click an icon and choose **Show When It Changes**. When the icon
changes, Barkeep shows it next to the arrow for 30 seconds (adjustable in
Settings → Menu Bar), then hides it again.

macOS can't photograph hidden icons, so Barkeep watches what it can:

- every few seconds: the icon's **status text** (many apps include their
  state there), its **width**, and whether the app **re-added** the icon;
- right after the **network changes** (for example, a VPN connecting or
  dropping): a quick look at the watched icons' pictures;
- optionally every 2 or 10 minutes: the same quick look. Each look slides the
  icon into view for a moment.

Watched icons have a small bell in Layout.

## Presenter mode

Presenter mode hides every other app's icon and keeps your Mac and display
awake while you present. The clock and Control Center stay, and so does
macOS's own camera and screen-recording indicator.

- It **starts by itself** when you share or record your screen, and stops
  when you're done. Barkeep reads this from macOS's own screen-recording
  indicator. Turn it off in Settings → Menu Bar → Presenter mode.
- Start or stop it yourself with the **Presenting** tile in the quick panel,
  a shortcut, `barkeep present on`, or the Shortcuts action.
- Optionally it also **hides desktop icons**. That restarts Finder, so the
  screen flickers once.

While presenting, the arrow shows an eye-slash. Clicking it opens the Barkeep
Bar, so your hidden icons only appear if you choose to show them.

## A separate layout at your desk

Turn on **Separate layout at your desk** in Settings → Layout. Barkeep then
keeps two layouts: one for the laptop screen alone, and one for when an
external display is connected. It switches when you connect or disconnect a
display. Arrange your icons while docked to set up the desk layout.

## Keep awake

Click the **cup** in the menu bar (or right-click the arrow) for the quick
panel.

- **Set:** keep awake for 15 minutes, 1, 2 or 4 hours, or indefinitely (∞).
- **Add:** during a timed session, add 15 or 30 minutes, 1 or 2 hours.
- **⋯** for **until a time**, **while an app is running**, or **until
  downloads finish**.
- **Option-click the cup** to start or stop without opening the panel.

During a timed session the cup shows the **time left**, for example "42m" or
"1:05". You can turn that off in Settings → Keep Awake.

### Rules

Rules keep your Mac awake by themselves while all their conditions hold. Add
them in Settings → Keep Awake → **Add Rule**, from a ready-made rule or a
custom one:

- on power adapter
- an external display is connected
- the microphone is in use (calls)
- files are downloading
- a particular app is running
- a schedule, for example weekdays 08:00–17:00

Each rule can let the display sleep or keep it on.

### Options

- **Let the display sleep:** the Mac keeps running; only the screen turns
  off.
- **Keep me available:** while keeping awake, nudges the pointer by one pixel
  every few idle minutes, so Teams and Slack don't show you as Away.
- **Stop when battery is below** 5, 10 (the default), 20 or 30%.
- **Notify me when a session ends.**
- **Closed-lid mode:** keeps the Mac running with the lid closed, even
  without an external display. It asks for your administrator password each
  time you switch it, and Barkeep turns it off again when it quits. A closed
  Mac that keeps running gets warm, so don't put it in a bag like that.

## Quick panel and toggles

Besides keep awake, the quick panel has one-click toggles:

| Toggle | What it does |
|---|---|
| Presenting | Presenter mode on or off |
| Dark Mode | Switches the system appearance (asks once for permission to control System Events) |
| Microphone | Mutes or unmutes the default microphone for every app |
| Hide Desktop | Hides the icons on your desktop (restarts Finder) |
| Hidden Files | Shows or hides dotfiles in Finder (restarts Finder) |
| Sleep Display | Turns the screen off right away |

Choose which toggles appear in Settings → Toggles.

## Search and commands

Press **⌃⌥⌘M**. Type part of an icon's name to find it, hidden or not, and
press Return to open it. Hidden icons come first, labelled with where they
are.

You can also type a command:

| Type | To |
|---|---|
| `awake`, `awake 2h`, `awake 90`, `awake forever` | Keep awake |
| `awake +30` | Add time |
| `stop` | Stop keeping awake |
| `present` | Presenter mode |
| `dark` | Dark mode |
| `mute` | Mute or unmute the microphone |
| `desktop`, `hidden files`, `sleep` | The other toggles |
| `clipboard` | Clipboard history |
| `arrange` | Settings → Layout |
| `settings`, `rules`, `shortcuts`… | That Settings pane |

## Clipboard history and the drop tray

Press **⌃⌥⌘V** for **clipboard history**: text, links, images and files you
copied, newest first. Type to search, use the arrow keys, and press Return to
paste into the app you were using. Right-click an entry to copy, pin or
delete it. Pinned entries stay at the top and are never cleared.

Barkeep never records copies from password managers. They mark their copies
as private, and Barkeep also skips 1Password, Bitwarden, Passwords, Keychain
Access and others by name. Text history is kept across restarts (you can turn
that off). Images stay in memory only. Turn history off entirely in Settings →
Clipboard.

The **drop tray** appears under the notch as soon as you start dragging files
in any app. Drop them there to hold them. While it holds files, a small tab
stays under the notch. Hover over it or click it to see them, then drag them
out wherever you need them. The tray only remembers where the files are; it
never moves or copies them. The **Shelf** tab in clipboard history shows the
same files. Turn off the tray or its tab in Settings → Clipboard.

## Appearance

Settings → Appearance:

- **Tint the menu bar** (off by default) with a colour or gradient, full width,
  as a rounded pill, or split around the notch, with an optional border and
  shadow.
- **Space between icons:** less space fits more icons beside the notch.
  Apps pick up the new spacing when they next start. **Apply to System Icons**
  restarts the system's own icons; log out and back in to apply it
  everywhere. **Reset to Default** goes back to macOS's spacing.

## Automation

### Shortcuts

Barkeep adds these actions to the Shortcuts app: **Keep Mac Awake** (minutes),
**Stop Keeping Mac Awake**, **Set Presenter Mode**, **Show or Hide Menu Bar
Icons**, **Open Menu Bar Icon** (by app name) and **Show Clipboard History**.
Barkeep needs to be running.

### Terminal

`barkeep` is installed by `Scripts/install.sh`, or download it from the release
page and move it to `/opt/homebrew/bin`.

```
barkeep show | hide | toggle | all       hidden icons
barkeep bar | search | clipboard         panels
barkeep awake [minutes|+minutes|stop]    keep awake (no minutes = until stopped)
barkeep present [on|off]                 presenter mode (no argument = toggle)
barkeep open <app>                       open an app's menu bar icon
barkeep place <app> visible|hidden|alwaysHidden
barkeep watch <app> [off]                show the icon when it changes
barkeep icon <app> <text>|reset          replace an app's icon with text or an emoji
barkeep settings [pane]                  open Settings
```

### Links

For Raycast, Alfred, scripts and anything that can open a URL:

| Link | Does |
|---|---|
| `barkeep://toggle`, `barkeep://hide`, `barkeep://show-all` | Hidden icons |
| `barkeep://bar`, `barkeep://search`, `barkeep://clipboard` | Panels |
| `barkeep://keep-awake?minutes=60` (0 = indefinitely) | Keep awake |
| `barkeep://keep-awake/extend?minutes=30` | Add time |
| `barkeep://keep-awake/stop` | Stop |
| `barkeep://presenter`, `?on=1`, `?on=0` | Presenter mode |
| `barkeep://open?app=Mail` | Open an app's icon |
| `barkeep://place?app=Mail&row=hidden` | Move an icon |
| `barkeep://watch?app=Mail` (`&on=0` to stop) | Show when it changes |
| `barkeep://icon?app=Mail&label=✉️` (`&reset=1` to undo) | Custom icon |
| `barkeep://settings?pane=layout` | Settings |
| `barkeep://setup` | The setup guide |

## Troubleshooting

**The Barkeep Bar or search says "Allow Accessibility".** Turn on Barkeep in
System Settings → Privacy & Security → Accessibility. If it's already on,
switch it off and on again. That's sometimes needed after updating Barkeep.

**Hidden icons show app icons instead of their real pictures.** Allow
Screen Recording and relaunch Barkeep, then use Layout → **Refresh Pictures**.

**My pointer moved by itself for a moment.** When Barkeep moves an icon, it
uses the same ⌘-drag you would. It hides the pointer during the move and puts
it back afterwards. Moves happen when you arrange icons, open a hidden icon,
or when Barkeep puts an icon back where it belongs. If it happens over and
over, please open an issue. Barkeep gives up on an icon after two tries, so
it shouldn't happen.

**An icon won't stay where I put it.** Some apps re-create their icon when
they change state. Put it where you want in Layout; Barkeep remembers it by
app and name.

**macOS says it can't verify Barkeep.** See [Download](../README.md#download).
That happens once, because Barkeep isn't notarized yet.

**Uninstalling.** Quit Barkeep (quick panel → power button) and move it to the
Trash. Its settings are in
`~/Library/Preferences/io.github.marvika.Barkeep.plist`, and its pictures and
clipboard history are in `~/Library/Application Support/Barkeep`. Remove
Barkeep from Accessibility and Screen Recording in Privacy & Security.
