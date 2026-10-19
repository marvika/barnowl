<p align="center">
  <img src="docs/images/hero.png" alt="Barn Owl: a tidy menu bar with the Perch and the keep-awake panel open" width="900">
</p>

<p align="center">
  <b>A tidy menu bar, a Mac that stays awake, and room on your disk.</b><br>
  One friendly owl. Free and open source, for macOS 26 Tahoe and later.
</p>

<p align="center">
  <a href="https://github.com/marvika/barnowl/releases/latest"><img src="https://img.shields.io/github/v/release/marvika/barnowl?label=download&color=8C87FF" alt="Download the latest release"></a>
  <a href="https://github.com/marvika/barnowl/actions/workflows/ci.yml"><img src="https://github.com/marvika/barnowl/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/macOS-26%2B-3D3A8F" alt="macOS 26 and later">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-F0B04F" alt="MIT License"></a>
</p>

```bash
brew install --cask marvika/tap/barn-owl
```

<p align="center">
  or <a href="https://github.com/marvika/barnowl/releases/latest"><b>download the app</b></a> ·
  <a href="docs/user-guide.md">User guide</a> ·
  <a href="docs/how-it-works.md">How it works</a> ·
  <a href="CHANGELOG.md">What's new</a>
</p>

<p align="center">
  <img src="docs/images/demo.gif" alt="Barn Owl in action: hidden icons settle onto the Perch, then the quick panel starts keeping the Mac awake for an hour and the owl's eyes open" width="600">
</p>

## What it does

|  |  |
|---|---|
| 🦉 **Tidies your menu bar** | Hides the icons you rarely use and shows them on the **Perch** when you want them. Nothing gets lost behind the notch. [More](#a-tidy-menu-bar) |
| ☕️ **Keeps your Mac awake** | For an hour, until a time, while an app runs, or by rules: during calls, on power at your desk. [More](#keep-awake) |
| 🧹 **Frees up disk space** | Finds caches, build files and forgotten installers, cleans the safe ones in one click, and maps your disk. [More](#the-barn-free-up-disk-space) |
| ⚡️ **Gets things done** | Search every icon and run commands with ⌃⌥⌘M, quick toggles, clipboard history, and a Nest for files you're dragging around. [More](#and-the-everyday-tools) |

## Why Barn Owl?

- **Several apps' worth in one.** Menu bar hiding, keep-awake, a disk cleaner,
  a clipboard and a file shelf, all sharing one small menu bar icon.
- **Made for macOS 26.** Liquid Glass, notched MacBooks, and Apple silicon.
- **Safe by design.** Clean-ups are locked to their own folders, go to the
  Trash where they can, and ask before anything that can't be undone.
- **Private.** No account, no analytics. Its only network request is the
  update check.
- **Light.** Under 1% CPU at idle, and it only listens to the mouse when a
  feature needs it.
- **Free and open source,** under the MIT license.
- **And it has an owl.** It wears shades while you present, gets coffee on
  long sessions and celebrates when you free up space.

## A tidy menu bar

<img src="docs/images/perch.png" alt="The Perch showing hidden and always-hidden icons" width="420" align="right">

Click the arrow, press **⌃⌥⌘B**, hover or scroll, and your hidden icons
appear on the **Perch**, a strip under the menu bar. Click any icon there and
its menu opens as usual.

- **Arrange by dragging** in Settings → Layout, with real pictures of every
  icon. Barn Owl moves the real icons for you.
- **Groups:** one icon that opens a strip of others, like a briefcase for
  your VPN, mail and chat.
- **Custom icons:** swap any app's icon for a symbol, an emoji or "VPN".
- **Show when it changes:** a hidden icon pops into view when it changes,
  so a dropped VPN doesn't go unnoticed.
- **Presenter mode:** share your screen and every icon hides, then comes
  back when you stop.

<br clear="right">

## Keep awake

<img src="docs/images/quick-panel.png" alt="The quick panel: the owl with 2:14:56 left, add-time buttons, rules, round toggles and free disk space" width="340" align="right">

Click the owl for the quick panel. Its eyes are open while your Mac is kept
awake, and the time left counts down beside it.

- **For a while,** until a time, while an app runs, or until downloads finish.
- **Rules** that switch it on by themselves: on power with an external
  display, during calls, on weekdays 08:00–17:00. Combine conditions as you
  like.
- **Keep me available** stops Teams and Slack from marking you Away.
- **Closed-lid mode** keeps a MacBook running with the lid shut while it's awake, on battery too.
- It stops below a battery level you choose.

The same panel has one-click toggles for presenter mode, dark mode, the
microphone, desktop icons, hidden files and sleeping the screen.

<br clear="right">

## The Barn: free up disk space

<img src="docs/images/barn-tidy.png" alt="The Barn: a storage bar, a button to free up 22 GB, and what's safe to clean, listed biggest first" width="760">

Click the disk row in the quick panel, or search for "disk", and the owl
shows how your disk is used and what it can safely clean, sorted by how safe
it is:

- **Safe to clean:** browser and app caches, Xcode build files, iPhone
  updates, npm, pip and other tool caches. One click frees them all.
- **Check first:** macOS installers left behind, apps you haven't opened in
  six months, big old downloads. You pick what goes, and Undo puts it back.
- **Only you know:** iPhone backups, the Photos library, Docker. Shown with
  advice, never cleaned for you.

**Explore** maps the whole disk, about three million files in half a minute,
as rings to click through, with the biggest files by kind and a basket for
what can go.

<img src="docs/images/barn-explore.png" alt="Explore: a ring map of the disk with the biggest folders listed beside it" width="760">

## And the everyday tools

<img src="docs/images/search-commands.png" alt="Search showing keep-awake commands for the query awake" width="460">

- **Search, ⌃⌥⌘M:** find any menu bar icon, even hidden ones, or type a
  command: `awake 2h`, `awake +30`, `dark`, `present`, `mute`, `disk`.
- **Clipboard history, ⌃⌥⌘V:** text, links, images and files. Pin what you
  use often. Copies from password managers are never recorded.
- **The Nest:** start dragging files and it slides out under the notch. Drop
  them there, then drag them out later, wherever you need them.

<p>
  <img src="docs/images/clipboard.png" alt="Clipboard history with a pinned entry, a link and a file" width="420">
  <img src="docs/images/drop-tray.png" alt="The Nest holding three files, with a button to drag them all out" width="380">
</p>

## Meet the owl

<img src="docs/images/owl-moods.png" alt="The owl wide awake, hooting, in shades, petted, in a party hat, and asleep in a nightcap" width="900">

The owl's eyes are open while it keeps your Mac awake and shut when your Mac
may sleep. It wears a headset during calls and shades while you present,
covers its eyes when you copy a password, and says "Nom!" when you feed it a
file. There are 40 owl moments to find. Pick its colours (Golden Barn, Ghost
Owl, Ember or Moonlit Lilac) and its personality in Settings → Appearance.
With Reduce Motion on, it keeps still.

## Install

Requires macOS 26 Tahoe or later, on Apple silicon or Intel.

```bash
brew install --cask marvika/tap/barn-owl
```

This also puts the `barnowl` command on your PATH. Or download
**BarnOwl-x.y.z.zip** from the
[latest release](https://github.com/marvika/barnowl/releases/latest), drag
**Barn Owl** into Applications and open it. A short setup guide takes it from
there.

<p>
  <img src="docs/images/setup-welcome.png" alt="Setup: welcome" width="270">
  <img src="docs/images/setup-display.png" alt="Setup: where hidden icons appear, and permissions" width="270">
  <img src="docs/images/setup-done.png" alt="Setup: the owl celebrating in a party hat" width="270">
</p>

Barn Owl is signed and notarized by Apple, and it updates itself, asking
before it installs anything. On macOS 27, hiding works per app rather than
per icon and has had less testing; see
[how it works](docs/how-it-works.md#hiding).

## Keyboard shortcuts

| | |
|---|---|
| Show or hide hidden icons | ⌃⌥⌘B |
| Search the menu bar, run a command | ⌃⌥⌘M |
| Clipboard history | ⌃⌥⌘V |
| Show every icon | Option-click the arrow |
| Keep awake on or off | Option-click the owl |

Set your own in Settings → Shortcuts.

## Automation

Shortcuts actions, a `barnowl` command for the Terminal (`barnowl awake 90`,
`barnowl open vpn`, `barnowl present on`) and `barnowl://` links for Raycast,
Alfred and scripts. See the [user guide](docs/user-guide.md#automation).

## Privacy and permissions

Barn Owl works entirely on your Mac. It has no accounts and no analytics. Its
only network request is checking GitHub for new versions, which sends nothing
about you or your Mac.

- **Accessibility** lets it list, move and open menu bar icons.
- **Screen Recording** lets it show real pictures of hidden icons. Without
  it, you see app icons instead.
- **Full Disk Access** (optional) lets the Barn look in the Trash, Mail and
  Safari's caches, and iPhone backups.

Clipboard history stays on your Mac and never saves images to disk.

## Building from source

Requires Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
Scripts/install.sh
```

This builds a Release copy, installs it in /Applications and starts it. For
development, tests, the demo copy used for screenshots and the release
process, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Contributing

Bug reports, ideas and pull requests are welcome; see
[CONTRIBUTING.md](CONTRIBUTING.md). Please report security problems
privately, as [SECURITY.md](SECURITY.md) describes.

## Credits

Barn Owl learned from [Hidden Bar](https://github.com/dwarvesf/hidden) and
[Frost](https://github.com/frostbar/frost), both MIT; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). It also learned from reading
[Ice](https://github.com/jordanbaird/Ice) and
[Thaw](https://github.com/thaw-app/Thaw), both GPL-3; no code was copied.
The Barn's approach to safe cleaning was inspired by
[Mole](https://github.com/tw93/mole) (GPL-3), and its map by
[DaisyDisk](https://daisydiskapp.com); no code was copied.
Hotkeys use [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts),
and updates use [Sparkle](https://sparkle-project.org).

## License

[MIT](LICENSE)
