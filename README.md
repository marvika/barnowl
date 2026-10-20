<p align="center">
  <img src="docs/images/hero.png" alt="Barn Owl, the owl that runs your menu bar: the owl beside the island at the notch asking a question from a coding agent, the quick panel keeping the Mac awake with owlets, plan limits and a healthy disk, and four pixel owlets on a branch at dusk" width="900">
</p>

<p align="center">
  Tidy icons, a Mac that stays awake, room on your disk, and an eye on your coding agents.<br>
  One friendly owl. Free and open source, for macOS 26 Tahoe and later.
</p>

<p align="center">
  <a href="https://github.com/marvika/barnowl/releases/latest"><img src="https://img.shields.io/github/v/release/marvika/barnowl?label=download&color=8C87FF" alt="Download the latest release"></a>
  <a href="https://github.com/marvika/barnowl/actions/workflows/ci.yml"><img src="https://github.com/marvika/barnowl/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/macOS-26%2B-3D3A8F" alt="macOS 26 and later">
  <img src="https://img.shields.io/badge/notarized-by%20Apple-6FCF97" alt="Signed and notarized by Apple">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-F0B04F" alt="MIT License"></a>
</p>

```bash
brew install --cask marvika/tap/barn-owl
```

<p align="center">
  or <a href="https://github.com/marvika/barnowl/releases/latest"><b>download the app</b></a> ·
  <a href="#install">Install guide</a> ·
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
| ☕️ **Keeps your Mac awake** | For an hour, until a time, while an app runs, or by rules: during calls, on power at your desk, while an agent works. [More](#keep-awake) |
| 🐣 **Watches your coding agents** | Claude Code, Codex and others as pixel owlets: who's working, who needs you, and what got done. [More](#your-coding-agents) |
| 🧹 **Frees up disk space** | Finds caches, build files and forgotten installers, cleans the safe ones in one click, and maps your disk. [More](#the-barn-free-up-disk-space) |
| ⚡️ **Gets things done** | Search every icon and run commands with ⌃⌥⌘M, quick toggles, clipboard history, and a Nest for files you're dragging around. [More](#and-the-everyday-tools) |

## Why Barn Owl?

- **Several apps' worth in one.** Menu bar hiding, keep-awake, a disk
  cleaner, a clipboard, a file shelf and a home for your coding agents, all
  behind one small owl.
- **Made for macOS 26.** Liquid Glass, notched MacBooks and Apple silicon,
  from the ground up.
- **Only what you want.** Every feature can be switched off, and a feature
  that's off does no work at all.
- **Safe by design.** Clean-ups are locked to their own folders, go to the
  Trash where they can, and ask before anything that can't be undone.
- **Private.** No account, no analytics. Its only network request is the
  update check.
- **Light.** Under 1% CPU at idle. It only listens to the mouse, or looks at
  your agents, when a feature needs it.
- **Free and open source,** under the MIT license.
- **And it has an owl.** It wears shades while you present, gets coffee on
  long sessions, glances at its owlets when one needs you, and celebrates
  when you free up space.

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
  display, during calls, while a coding agent works, on weekdays
  08:00–17:00. Combine conditions as you like.
- **Keep me available** stops Teams and Slack from marking you Away.
- **Closed-lid mode** keeps a MacBook running with the lid shut while it's
  awake, on battery too.
- It stops below a battery level you choose.

The same panel has one-click toggles for presenter mode, dark mode, the
microphone, desktop icons, hidden files and sleeping the screen.

<br clear="right">

## Your coding agents

<p align="center">
  <img src="docs/images/roost.gif" alt="An agent asks at the notch, the island opens to its question, the quick panel shows the owlets, then the Roost's Now view and its pixel tree" width="760">
</p>

Run Claude Code, Codex, Mistral Vibe, Copilot CLI, OpenCode or Gemini CLI, and each session
gets a pixel **owlet** that shows what it's doing: typing, running a command,
searching, thinking, napping, or holding up a sign when it needs you. Start
ten at once and you still see, at a glance, which one is waiting on you.

<img src="docs/images/quick-panel-agents.png" alt="The quick panel's owlets: agents on a branch, one asking a question with an Answer button, and the plan limits as moons" width="340" align="right">

- **In the menu bar,** a small owlet sits beside the owl while agents work,
  with a dot when one needs you.
- **In the quick panel,** every owlet on a branch, the one that needs you
  with what it's asking and an **Answer** button, and your plan limits as
  moons that wax as you use them.
- **Show** takes you to the exact Terminal or iTerm tab, or the exact chat in
  the Claude app.
- **Your Mac stays awake** while an agent works, and for five minutes after.
- **Teams and armies** of helpers stay readable: a few as hatchlings beside
  their owlet, a brood as a quiet grid of squares.

<br clear="right">

### The Roost

<img src="docs/images/roost-now.png" alt="The Roost: what needs you, who's working, and how today went" width="760">

The **Roost** is their home. It opens on what needs you, with the actual
question or command and how long it has waited; then who's working and with
how many helpers; what got done today; and how the day went, hour by hour
and repository by repository, with your plan limits beside it.

Switch to the **Tree** and every owlet sits on one pixel tree: a branch per
repository, a lantern by the one that needs you, a rain cloud over the one
that's stuck, nappers curled up in the hollow and finished owlets asleep in
the nest, under a sky that follows the time of day. Pop it out into its own
window and keep it on top.

<img src="docs/images/roost-tree.png" alt="The Roost's tree: a branch per repository, a lantern by the owlet that needs you, nappers in the hollow and finished owlets in the nest" width="760">

### The island

<img src="docs/images/island.png" alt="The island at the notch, showing a question from Claude Code with its options" width="420" align="right">

When an agent needs you, a small **island** grows out of the notch, with a
ring that counts down a question's minute. Hover to read the whole question
or command, then go straight to it.

If you like, answer Claude Code right there: **Allow Once**, **Deny**, its
own "don't ask again" rule (spelled out, so you know exactly what you're
allowing), or one of a question's options. Nothing is ever allowed without
your click, and the usual prompt takes over whenever you'd rather answer in
the terminal.

<br clear="right">

### On your desktop, and at the end of the week

A **desktop widget** keeps the Roost under a glass dome, changing with the
time of day. At the end of the week there's a **recap** to share, with your
repository names hidden unless you show them.

<p>
  <img src="docs/images/widget.png" alt="The desktop widget: the Roost under a glass dome, with one owlet needing you" width="420">
  <img src="docs/images/recap.png" alt="The weekly recap card: hours of agent work, the busiest times and the owlets on a branch" width="420">
</p>

Barn Owl reads the agents' own session files on your Mac, never keeps your
prompts or replies, and never reads a login. Don't use coding agents? Turn it
all off in Settings → General → Features. More in the
[user guide](docs/user-guide.md#coding-agents).

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
  command: `awake 2h`, `awake +30`, `dark`, `present`, `mute`, `disk`,
  `roost`.
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

Barn Owl needs **macOS 26 Tahoe or later**, on Apple silicon or Intel. It's
signed and notarized by Apple, so it opens like any other app.

### With Homebrew (recommended)

```bash
brew install --cask marvika/tap/barn-owl
```

This installs Barn Owl in Applications and puts the `barnowl` command on
your PATH. Open **Barn Owl** from Applications or Spotlight.

### Or download it

1. Download **BarnOwl-x.y.z.zip** from the
   [latest release](https://github.com/marvika/barnowl/releases/latest).
2. Double-click the zip if your browser didn't unzip it.
3. Drag **Barn Owl** into your **Applications** folder.
4. Open it. The owl appears in your menu bar, and a short setup guide starts.

<p>
  <img src="docs/images/setup-welcome.png" alt="Setup: welcome" width="200">
  <img src="docs/images/setup-display.png" alt="Setup: where hidden icons appear, and permissions" width="200">
  <img src="docs/images/setup-agents.png" alt="Setup: your coding agents as owlets, and the island at the notch" width="200">
  <img src="docs/images/setup-done.png" alt="Setup: the owl celebrating in a party hat" width="200">
</p>

### First launch

The setup guide walks you through where hidden icons appear, which icons
stay visible, your shortcuts, opening at login and the coding agents. macOS
asks for permissions only as each feature needs them:

| Permission | What it's for | Needed? |
|---|---|---|
| **Accessibility** | Listing, moving and opening menu bar icons | For hiding and arranging icons |
| **Screen Recording** | Real pictures of hidden icons on the Perch | Optional: without it you see app icons |
| **Automation** | Bringing an agent's Terminal or iTerm tab to the front; switching dark mode | Asked the first time you use it |
| **Notifications** | Telling you when an agent needs you and the island can't, or a session ends | Optional |
| **Full Disk Access** | Letting the Barn look in the Trash, Mail and Safari caches, and iPhone backups | Optional |

You can grant or revoke any of them later in System Settings → Privacy &
Security. Barn Owl's own Settings show whether Accessibility and Screen
Recording are on, with a button to turn each on.

### Updates

Barn Owl checks GitHub for new versions and asks before installing one. With
Homebrew you can also run `brew upgrade --cask barn-owl`.

### Uninstall

If you turned on **answering from the island** or **reset times for
Claude**, turn them off first in Settings → Agents, so Claude Code's
settings go back to how they were. (They do nothing once Barn Owl is gone,
so it's tidiness rather than necessity.) Then:

```bash
brew uninstall --zap --cask barn-owl
```

or quit Barn Owl and drag it from Applications to the Trash. Its settings
live in `~/Library/Preferences/io.github.marvika.BarnOwl.plist` and its
data in `~/Library/Application Support/Barn Owl`.

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
Alfred and scripts, such as `barnowl://roost` for the Roost. See the
[user guide](docs/user-guide.md#automation).

## Privacy

Barn Owl works entirely on your Mac. It has no accounts and no analytics. Its
only network request is checking GitHub for new versions, which sends
nothing about you or your Mac. Clipboard history stays on your Mac and never
saves images to disk.

For coding agents, Barn Owl reads the agents' session files in `~/.claude`,
`~/.codex` and `~/.vibe`, and the Claude app's session records and usage history. It
shows what an agent is waiting on you for while it waits, never keeps your
prompts or replies, and never reads a login. It changes Claude Code's
settings only if you turn on answering from the island or Claude's reset
times, after showing you the exact change and saving a backup. The details
are in [SECURITY.md](SECURITY.md).

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
