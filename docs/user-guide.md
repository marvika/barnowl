# Barn Owl user guide

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
- [Clipboard history and the Nest](#clipboard-history-and-the-nest)
- [The Barn: disk space](#the-barn-disk-space)
- [Coding agents](#coding-agents)
- [Appearance](#appearance)
- [The owl](#the-owl)
- [Automation](#automation)
- [Updates](#updates)
- [Troubleshooting](#troubleshooting)

## Getting started

When Barn Owl opens for the first time, a short setup guide walks you through
it. You can run it again any time from Settings → General → Setup guide.

Barn Owl asks for two permissions in **System Settings → Privacy & Security**:

| Permission | What it's for | Without it |
|---|---|---|
| Accessibility | Listing, moving and opening menu bar icons | Hiding still works; the Perch, search, arranging and groups don't |
| Screen Recording | Real pictures of hidden icons | You see app icons instead of the real icons |

macOS asks for a few more only when you first use something that needs them:

| Permission | What it's for | Without it |
|---|---|---|
| Automation: Terminal, iTerm | Bringing an agent's exact tab to the front when you choose Show or Answer | The app comes to the front, but not the tab |
| Automation: System Events | The Dark Mode toggle | Dark Mode can't switch from Barn Owl |
| Notifications | Telling you an agent needs you when the island can't, a keep-awake session ended, an update is ready, or the disk is nearly full | No notifications; the quick panel and the island still show everything |
| Desktop, Documents | The Barn looking through them; finding the repository of an agent working there | The Barn skips them; an owlet is named after its folder rather than its repository |
| Full Disk Access (optional) | The Barn looking in the Trash, Mail, Safari and iPhone backups | See [Full Disk Access](#full-disk-access) |

macOS applies Screen Recording only after Barn Owl restarts. The setup guide
and Settings offer a **Relaunch Barn Owl** button for that.

Turn on **Open at login** in Settings → General to keep your menu bar tidy
from the start.

## Hiding icons

Barn Owl adds an **arrow** to your menu bar, next to Control Center, and a
`|` divider left of it. Icons left of the divider are hidden.

- **Click the arrow** or press **⌃⌥⌘B** to see your hidden icons. Click again
  to hide them.
- **Option-click the arrow** to show everything, including always-hidden
  icons.
- **Right-click the arrow** for the quick panel.

### Where hidden icons appear

Choose in Settings → Menu Bar:

- **On the Perch:** a strip under the menu bar. Click an icon and
  Barn Owl brings it next to the arrow and opens its menu, then puts it back.
- **In the menu bar:** hidden icons slide back into the menu bar itself.
- **Automatic** (the default): the menu bar when there's room, the Perch
  when there isn't. On a notched MacBook that's usually the Perch,
  because only a few icons fit beside the notch. Icons that end up behind
  the notch always show on the Perch.

### Other options (Settings → Menu Bar)

- **Hide icons again automatically** after a few seconds (on by default).
  Barn Owl waits while your pointer is in the menu bar.
- **Always-hidden section:** a second `⋮` divider. Icons left of it stay
  hidden until you option-click the arrow, search for them, or open them from
  a group.
- **Show hidden icons when hovering over the arrow**, or **scroll over the
  menu bar** (down shows, up hides). Both are off by default.
- **New icons go:** hidden (the default) or in the menu bar.

## Arranging icons

Open **Settings → Layout**, or click **Arrange** in the Perch.

Every icon appears with its real picture in rows: **Menu bar**, **Hidden**,
**Always hidden**, and one row per group. Drag an icon to another row, or onto
another icon to put it right before that one. Barn Owl moves the real icon
straight away.

Right-click an icon for:

- **Always Show in Menu Bar**, **Hide**, **Always Hide**
- **Move to Group**
- **Replace Icon…** (see below)
- **Show When It Changes** (see below)

The clock and Control Center have a lock: macOS doesn't let anyone move them.

You can still ⌘-drag icons in the menu bar itself, as with any Mac, and
Barn Owl remembers that too.

**Refresh Pictures** in Layout fills in icons that show an app icon instead
of their real picture. Icons behind the notch or off screen can't be
photographed, so Barn Owl briefly brings each one into view.

### Icons stay where you put them

Barn Owl remembers which row each icon belongs to. When an app restarts and
macOS puts its icon somewhere else, Barn Owl moves it back. If it can't keep
an icon in place after two tries, it stops trying, so your pointer is never
kept busy.

## Groups and custom icons

**Groups** gather several icons behind one. In Settings → Layout click
**New Group**, give it a name and an icon, then drag icons into its row. The
group's icon appears in the menu bar. Click it for a strip with its icons, or
right-click it to edit. The icons themselves wait in the always-hidden
section.

**Custom icons** replace one app's icon with a symbol, an emoji or a bit of
text. Right-click the icon in Layout or the Perch and choose **Replace
Icon…**. Clicking your icon opens the app's menu directly. To go back,
delete the custom icon's group in Layout (Edit → Delete Group).

## Show when it changes

Right-click an icon and choose **Show When It Changes**. When the icon
changes, Barn Owl shows it next to the arrow for 30 seconds (adjustable in
Settings → Menu Bar), then hides it again.

macOS can't photograph hidden icons, so Barn Owl watches what it can:

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
  when you're done. Barn Owl reads this from macOS's own screen-recording
  indicator. Turn it off in Settings → Menu Bar → Presenter mode.
- Start or stop it yourself with the **Presenting** tile in the quick panel,
  a shortcut, `barnowl present on`, or the Shortcuts action.
- Optionally it also **hides desktop icons**, behind a picture of your
  wallpaper. Finder isn't touched, so the icons come back exactly where they
  were.

While presenting, the arrow shows an eye-slash. Clicking it opens the
Perch, so your hidden icons only appear if you choose to show them.

## A separate layout at your desk

Turn on **Separate layout at your desk** in Settings → Layout. Barn Owl then
keeps two layouts: one for the laptop screen alone, and one for when an
external display is connected. It switches when you connect or disconnect a
display. Arrange your icons while docked to set up the desk layout.

## Keep awake

Click the **owl** in the menu bar (or right-click the arrow) for the quick
panel. Its eyes are open while your Mac is kept awake, and during a timed
session the time left counts down in big numbers beside it.

- **One click to start:** 15 minutes, 1, 2 or 4 hours, or until you stop it
  (∞). While a timer runs, the same row adds 15 or 30 minutes, 1 or 2 hours.
- **⋯** for **until a time**, **while an app is running**, **until downloads
  finish**, starting over, and the options **Let Display Sleep** and **Keep
  Me Available**. When an option is on, a small tag under the buttons says so.
- **Toggles**, round like Control Center's: Presenting, Dark Mode, Mic,
  Desktop, Hidden Files and Sleep Screen. Pick which show in Settings →
  Toggles.
- **Option-click the owl** to start or stop without opening the panel, or use
  `barnowl://quick` to open the panel from a script.

During a timed session the owl shows the **time left**, for example "42m" or
"1:05". You can turn that off in Settings → Keep Awake.

### Rules

Rules keep your Mac awake by themselves while all their conditions hold. Add
them in Settings → Keep Awake → **Add Rule**, from a ready-made rule or a
custom one:

- on power adapter
- an external display is connected
- the microphone is in use (calls)
- files are downloading
- an agent is working (see [Coding agents](#keep-awake-while-an-agent-is-working))
- a particular app is running
- a schedule, for example weekdays 08:00–17:00

Each rule can let the display sleep or keep it on. When several rules hold
and one of them keeps the display on, it stays on.

### Options

- **Let the display sleep:** the Mac keeps running; only the screen turns
  off.
- **Keep me available:** while keeping awake, nudges the pointer by one pixel
  every few idle minutes, so Teams and Slack don't show you as Away. It
  pauses while the display may sleep, since a nudge would keep the display on
  and stop your Mac from locking.
- **Stop when battery is below** 5, 10 (the default), 20 or 30%.
- **Notify me when a session ends.**
- **Closed-lid mode:** while keep awake is on, the Mac keeps running with
  the lid closed, on battery too and without an external display. If you
  like, the screen locks as the lid closes (**Lock the screen when the lid
  closes**, off by default; never with an external display, where a closed
  lid is normal). Whenever keep awake is off, or Barn Owl quits, the
  Mac sleeps on lid close as usual. It asks macOS's power manager directly,
  as Amphetamine does, so it needs no password, also on company-managed Macs.
  The setup guide offers it on a MacBook. A closed Mac that keeps running
  gets warm, so don't put it in a bag like that.

## Quick panel and toggles

Besides keep awake, the quick panel has one-click toggles:

| Toggle | What it does |
|---|---|
| Presenting | Presenter mode on or off |
| Dark Mode | Switches the system appearance (asks once for permission to control System Events) |
| Microphone | Mutes or unmutes the default microphone for every app |
| Hide Desktop | Covers the icons on your desktop with your wallpaper; they come back where they were |
| Hidden Files | Shows or hides dotfiles in Finder (Finder quits and reopens, keeping its windows) |
| Sleep Display | Turns the screen off right away |

Choose which toggles appear in Settings → Toggles.

While coding agents are out, the quick panel also has an **Owlets** card;
see [Coding agents](#in-the-menu-bar-and-the-quick-panel).

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
| `roost`, `agents` | The Roost |
| `arrange` | Settings → Layout |
| `settings`, `rules`, `shortcuts`… | That Settings pane |

## Clipboard history and the Nest

Press **⌃⌥⌘V** for **clipboard history**: text, links, images and files you
copied, newest first. Type to search, use the arrow keys, and press Return to
paste into the app you were using. Right-click an entry to copy, pin or
delete it. Pinned entries stay at the top and are never cleared.

Barn Owl never records copies from password managers. They mark their copies
as private, and Barn Owl also skips 1Password, Bitwarden, Passwords, Keychain
Access and others by name. Text history is kept across restarts (you can turn
that off). Images stay in memory only. Turn history off entirely in Settings →
Clipboard.

The **Nest** appears under the notch as soon as you start dragging files in
any app, and the owl watches your pointer until you let go. Drop them there to
hold them. While it holds files, a small tab stays under the notch. Hover over
it or click it to see them, then drag them out wherever you need them, one at
a time or with **Drag all**.

A file leaves the Nest once you drop it somewhere; dropping it back on the
Nest keeps it. To keep files in the Nest instead, turn on **Keep files in the
Nest after dragging them out** in Settings → Clipboard.

The Nest only remembers where the files are. Where you drop them decides what
happens, as with any drag: Finder moves a file to another folder on the same
disk, and copies it to another disk (hold Option to copy instead). Files you
move or delete elsewhere leave the Nest by themselves. The **Nest** tab in
clipboard history shows the same files. Turn off the Nest or its tab in
Settings → Clipboard.

## The Barn: disk space

Open the Barn from the disk row in the quick panel, by searching for "disk"
or "barn", with `barnowl barn`, or with `barnowl://barn`.

The bar at the top adds up to your whole disk: your apps and files, macOS
itself, system data (swap, recovery and startup files, snapshots), what's
**purgeable** (caches, iCloud copies and snapshots macOS removes by itself
when it needs room) and what's free. Finder counts purgeable space as free.

### Tidy up

The owl looks in the places it knows and sorts what it finds by how safe it
is. Each row says how much you'd get back and what happens when you clean it.

- **Safe to clean:** browser caches, Xcode build files, simulator caches,
  iPhone and iPad update files, and the caches of npm, pnpm, Yarn, pip,
  CocoaPods, Swift packages, Go and Cargo. Apps and tools make them again
  when they need them. **Free Up** cleans all of these at once, after showing
  you the list. Where a tool has its own clean-up command (`npm cache clean`,
  `pnpm store prune`, `pip cache purge`), Barn Owl uses it.
- **Check first:** probably fine, but have a look. You pick what goes:
  - macOS installers left in Applications after an upgrade;
  - apps you haven't opened in six months (not Apple's; their settings stay);
  - big, old downloads: 200 MB or more, arrived over three months ago;
  - old installers (disk images and packages) in Downloads;
  - other apps' caches and logs, and attachments Mail copied when you
    opened them;
  - Device Support files and Gradle caches, removed for good after you
    confirm;
  - Homebrew's downloads and old versions (`brew cleanup --prune=all`) and
    simulators for iOS versions you no longer have (`xcrun simctl delete
    unavailable`), each after you confirm.

  Most of these go to the Trash, so **Undo** puts them back, and **Empty from
  Trash** removes just those, leaving the rest of your Trash alone. A long
  list has a search field.
- **Only you know:** iPhone backups, the Photos library, Xcode archives,
  simulator devices and Docker. Shown with advice, never cleaned by Barn Owl.

How it stays safe:

- Each clean-up can only touch its own folders, checked when it's offered and
  again right before anything is removed, with every link followed. Things
  you pick must be directly inside the folder and still match what was offered
  (the right kind, old enough).
- Never Apple's own caches, password managers', VPNs' or security tools'.
- Nothing is cleaned while its app is open ("Quit Xcode first") or while a
  build or the tool itself is running.
- Anything that can't be undone asks first and says what goes.
- Everything it does is written to `~/Library/Logs/Barn Owl/cleanup.log`.

Things moved to the Trash still take space until they're gone from the Trash.

### Explore

**Look Through the Disk** scans everything, usually in under a minute, and
draws a ring map, starting at your home folder: the centre is the folder
you're in, each ring a level deeper, each slice as wide as its share. Hover
to see what it is, click a folder to go in, click the centre (or press ←) to
go back, and **Whole Disk** in the path shows everything. Beside it, the
folder's contents biggest first, with a word on what system folders are, or
the **Biggest Files** anywhere, narrowed by kind (videos, disk images and
archives, music, pictures, documents).

Press Space for Quick Look, → to open a folder, or Delete to put it in the
**basket**; right-click to show it in Finder or copy its path. **Move to
Trash…** lists what's in the basket and asks first; anything that changed
since the scan is kept. The basket never takes anything from iCloud Drive,
cloud storage, Mail, Messages, app data or the system.

Sizes are what files really take on disk. Hard links count once, iCloud
files that aren't downloaded count as nothing (and are never downloaded),
and other disks are left out.

### Full Disk Access

Without it, the owl can't see the Trash, Mail, Safari, iPhone backups or other
apps' private folders; Explore shows them as locked. To allow it, open
**System Settings → Privacy & Security → Full Disk Access** and turn on Barn
Owl (the Barn has a button that goes straight there).

### Keep it clean

At the bottom of Tidy Up: **Warn me when the disk is nearly full** (on by
default, at most once a day, when less than 10 GB or a twentieth of the disk
is free), and **Look for things to tidy once a week** (off by default). Both
only tell you; nothing is cleaned without you.

## Coding agents

Barn Owl shows the coding agents running on your Mac as pixel **owlets**:
Claude Code, Codex, Copilot CLI, OpenCode, Gemini CLI, and Cursor's agent,
Droid, Goose, Crush, Aider and Amp. Each owlet shows what its agent is doing,
and Barn Owl tells you when one needs you. Their home is the **Roost**.

Start an agent in any folder and its owlet appears: Claude Code's within a
second or two, other agents' within 15 seconds (a minute, if none has run for
a while). Settings → Agents → **On this Mac** lists which agents Barn Owl
found and how many are running.

How much Barn Owl can tell depends on the agent:

| Agent | What its owlet shows |
|---|---|
| Claude Code, in a terminal, the Claude app's Code tab or the Agent SDK | Everything below: what it's doing, its helpers, when it needs you and what it asks, failed commands, pull requests, plan limits |
| Codex | Working, running commands, editing, stuck, paused for the plan limit, done; and its plan limits |
| The others | Working or resting, from whether it's using the processor |

To turn the whole feature off, switch off **Coding agents** in Settings →
General → Features (or **Show coding agents as owlets** in Settings →
Agents). Off means off: nothing is read or watched, and the owlets, the
island, the widget and the keep-awake rule all rest.

### What the owlets are doing

Each agent has its own colour, borrowed from the owl's: Claude Code golden,
Codex and Gemini CLI ghost white, Copilot CLI lilac, OpenCode ember.

| Owlet | Means |
|---|---|
| Typing | Editing a file |
| Searching | Reading or searching files |
| Running a command | A command, a build or a test run |
| Thinking | Working on its next step |
| Browsing | Fetching a page or searching the web |
| Starting a helper | A helper (subagent) has just hatched |
| Waiting for its helpers | Its helpers are doing the work |
| Fixing | Still at it after three failed commands in a row |
| Needs you | Waiting for your permission. On the tree, a lantern hangs beside it |
| Has a question | Waiting for your answer |
| Stuck | Stopped after three failed commands in a row. On the tree, a small rain cloud |
| Paused for the plan limit | Having tea until the limit resets |
| Offline | Can't reach the internet |
| Your turn | Finished a turn that took two minutes or more, in the last hour |
| Shipped | Just opened a pull request |
| Resting | Waiting for your next prompt |
| Napping | Idle for over ten minutes |

A Claude Code session's **helpers** (subagents) sit beside it: up to five as
hatchlings, more as a small flock.

### In the menu bar and the quick panel

While any agent works, a small owlet sits beside the owl in the menu bar,
with a dot when one needs you or is stuck, and the owl glances at it. Point
at the owl to see how many are working and which needs you. Turn the owlet
off in Settings → Agents.

The quick panel has an **Owlets** card:

- **Every owlet on a branch,** in a small night scene. Owlets that have
  napped a while curl up together at the end, and "+3" says how many more
  there are. Point at an owlet to see what it's doing, click it to go to it,
  and right-click it for more.
- **The one that most needs you** (or is stuck, or just finished): what it's
  asking, how long it has waited (for a question, how long is left), and
  **Answer** or **Show**.
- **One line for the rest:** "3 busy (12 helpers) · 1 stuck · docs shipped
  2 min ago".
- **Your plan limits** as moons (see below).
- **Your week in the Roost,** from Friday afternoon to Sunday (see below).
- **Hidden (2)** shows owlets you've hidden, until the panel closes.

**Roost ›** opens the Roost.

### The Roost

Open it with **Roost ›** in the quick panel, by searching for "roost" or
"agents", from Settings → Agents, with `barnowl://roost`, or by clicking the
widget. The top says how many owlets are out and how many need you. With
more than one repository, a menu there lets you show just one of them.

**Now** is the workbench:

- **Needs you:** the first one as a card with the actual question and its
  numbered options, or the whole command, file or address. It says how long
  it has waited, or for a question, a ring counts down the time left to
  answer. **Answer in Terminal** (or iTerm, or Claude), or press Return.
  Others waiting get a line each.
- **Working:** each owlet on its own twig, with what it's doing and for how
  long. A small team of helpers sits on a sub-twig with their roles; a big
  brood shows as squares, lilac working and green done. Double-click a row
  to go to it.
- **Done today:** owlets that finished or shipped, and sessions that ended
  today.
- **Napping:** one quiet row; **See All** opens it.
- **Today**, on the right: how long agents worked and the most at once, an
  hour-by-hour chart (lavender for work, amber for time spent waiting on
  you), your plan limits, and time by repository. **Open the full flight
  log** draws a line per repository through the day: working, waiting for
  you, and paused for a plan limit.

Today's numbers carry on across restarts of Barn Owl.

**Tree** puts every owlet on one pixel tree, a branch per repository. A
branch grows leafier the more work it saw today. The owlet that needs you
sits on top with a lantern, one that's stuck has a rain cloud, nappers curl
up in the hollow of the trunk, and owlets that finished today sleep in the
nest in the crown. Click an owlet to see it beside the tree: its state,
where it runs, its folder and branch, when it started, what its last turn
changed ("6 files changed · tests pass"), and its helpers with their tasks.
Double-click to go to it.

The sky follows the time of day and tonight's real moon. To keep it the
same, pick **Always Dusk**, **Always Night** or **Plain** in Settings →
Agents → The Roost's sky.

The button at the top right pops the tree out into its own **Roost Tree**
window, small enough to keep beside your work. Its pin button, **Keep on
Top**, keeps it above other windows. The owlets hold still while a window is
hidden behind others, and with Reduce Motion, Still or Low Power Mode on.

### Going to a session

**Show** and **Answer** take you to the session:

- In **Terminal** and **iTerm**, to the very tab it runs in. The first time,
  macOS asks whether Barn Owl may control that app (Automation).
- In the **Claude app**, to the very chat.
- In another app (VS Code, Warp, Ghostty…), that app comes to the front.

Right-click an owlet, anywhere, for **Show**, **Open in** your editor,
**Open in Terminal**, **Reveal in Finder**, **Hide**, **Mute**, and **Keep
the Mac Awake While It Works**. Pick the editor in Settings → Agents → Open
projects in: VS Code, Cursor, Zed, Xcode, Windsurf, IntelliJ IDEA, PyCharm,
WebStorm, GoLand, Sublime Text, Nova or BBEdit, whichever you have. A session in a worktree
opens its own folder.

### The island at the notch

When an agent needs you, a small island grows out of the notch, or hangs
from the top of the screen on a Mac without one. It says who and what in
one line. Hover over it to open it: the whole question with its options, or
the whole command (a long one scrolls), and **Answer in Terminal**. When
more are waiting, it says so, and **and 2 more in the Roost** opens the
Roost. Clicks pass through everywhere but the island itself.

Choose when it shows in Settings → Agents → Show at the notch:

- **When One Needs You** (the default): when an agent needs you or is stuck,
  and for a few seconds when one finishes a task.
- **While Agents Work:** quietly while any agent works, growing when one
  needs you.
- **Off.**

It stays away while you present (presenter mode starts by itself when you
share your screen) and while an app is full screen. It never asks you about a
session whose app is already in front, and never shows a muted repository or
a hidden owlet.

### Answering from the island

You can answer Claude Code's permission prompts and questions right in the
island, without switching apps. It's off by default. Turn it on in Settings
→ Agents → **Answer from the island** → **Turn On…**. The island needs to be
on, and Barn Owl needs to be in your Applications folder, so Claude Code can
always find it.

In the island you then get:

- for a permission prompt: **Deny** and **Allow Once**, and when Claude Code
  offers its own "don't ask again", **Always allow** followed by exactly what
  it covers, such as "Always allow npm test commands" or "Always allow
  www.example.com, this session";
- for a question: its options;
- and always **Answer in Terminal** (or whichever app it runs in), to answer
  there instead.

How it keeps you safe:

- Nothing is allowed without your click. No button is the default, so a
  stray Return never allows anything, and the buttons only take clicks after
  a short moment, and again when the request changes.
- Always allow adds only the rule Claude Code itself suggests, as its own
  "don't ask again" would, and only when that rule fits on the button.
- A tool without an obvious target shows its name and every argument, so
  nothing is allowed unseen.

It steps aside, and Claude Code shows its usual prompt, when:

- Barn Owl isn't running, or quits;
- you're already in that session's app when it asks, or switch to it;
- you choose **Answer in Terminal**, or Show or Answer anywhere else;
- the island can't show it: it's off, you're presenting, or an app is full
  screen;
- the session is hidden or its repository muted;
- you answer somewhere else first, such as in the Claude app;
- or ten minutes pass.

Questions with several parts, or where you can pick more than one answer,
always go to the usual prompt.

**What changes.** Before anything changes, Barn Owl shows the hooks setting
as it is now and as it will be, and saves a copy of
`~/.claude/settings.json` beside it, as `settings.json.barnowl-backup`. That
copy is made once, the first time Barn Owl changes the file, and only you
can read it. Then it adds two hooks to the file, keeping any of yours: one
for **PermissionRequest** (any tool) and one for **PreToolUse** (only
AskUserQuestion). Both run the same command:

```
b='/Applications/Barn Owl.app/Contents/MacOS/Barn Owl'; [ -x "$b" ] && exec "$b" --answer; :
```

Barn Owl writes the file back neatly formatted, with its keys in
alphabetical order, so it may look different in an editor even where its
contents haven't changed.

**To undo it,** click **Turn Off**: Barn Owl removes its two hooks and
leaves the rest as it is. If you remove Barn Owl without turning it off, no
harm is done: the command does nothing when Barn Owl is gone, and Claude
Code asks as usual.

### Notifications

Settings → Agents → Notifications:

- **When an agent needs you:** a permission prompt, a question, or stuck
  after failures.
- **When a long task finishes,** where long means at least 3 minutes (2, 5,
  10 or 30 if you prefer).

Barn Owl only notifies you when the island can't show it (you're presenting,
an app is full screen, or the island is off) or you've been away from the
Mac for a couple of minutes, and never for a session whose window is in
front of you. Click a notification to go to the session. Once a session
that needed you moves on, its notification goes away.

Muted repositories never notify, nor do owlets hidden for today, or
scripted and scratch sessions while they're hidden. An owlet hidden until it
needs you, or a hidden repository, still tells you when it needs you.

**Tell me at 80%, and when a limit resets** adds a note when a plan window
passes 80%, and another when a window that was that high starts again.

The first time Barn Owl has something to say, macOS asks whether to allow
its notifications.

### Plan limits

Under the owlets, in the Roost and on the widget, Claude's and Codex's
5-hour and weekly windows show as moons that wax as you use them and are new
again when the window resets: "38% · resets 19:30". When a window is filling
fast, the Roost says when it would run out at the recent pace. A reading
over half an hour old is faded and dashed, and says when it's from: "43% ·
as of 16:44".

Where the numbers come from:

- **Claude:** the Claude app's own usage history, which the app saves now
  and then while it runs. It has no reset times, so a 5-hour reading is
  shown for five hours at most, and a weekly one for a week, as "as of".
- **Codex:** its session logs, with reset times, as Codex reports them as it
  works. They're kept for six hours.
- **Claude's reset times:** Claude Code's status line, if you turn that on
  (below).

Barn Owl never asks a server for these, and never reads a login, a token or
a cookie. Turn plan limits off in Settings → Agents → Show plan limits.

#### Reset times for Claude

Claude Code hands its status line your plan usage, with reset times. Barn
Owl can take those on the way past. Turn it on in Settings → Agents → Plan
limits → **Reset times for Claude** → **Turn On…**.

**What changes.** As with answering, Barn Owl first shows the status line
setting as it is now and as it will be, and saves the backup (once). Then
the `statusLine` command in `~/.claude/settings.json` becomes:

```
b='/Applications/Barn Owl.app/Contents/MacOS/Barn Owl'; [ -x "$b" ] && exec "$b" --statusline -- 'your command'; your command
```

Each time Claude Code updates its status line, Barn Owl saves only the two
windows' percentages and reset times, then runs your own command with the
same input. So your status line looks exactly as before, and keeps its
padding and refresh interval. If Barn Owl is moved or deleted, the command
runs yours directly. After an update, Barn Owl points it at the new copy by
itself.

Only Claude Code in a terminal runs a status line. Sessions in the Claude
app's Code tab don't, so they don't pass on reset times.

**To undo it,** click **Turn Off**: Barn Owl puts back exactly the status
line you had (or none) and deletes the readings it saved. You can also
restore `~/.claude/settings.json.barnowl-backup` yourself; it's the file as
it was before Barn Owl first changed it, so it doesn't have changes you've
made since.

### Keep awake while an agent is working

The first time Barn Owl sees an agent, it adds a rule to Settings → Keep
Awake: **An agent is working**. It keeps your Mac and its screen awake while
any agent works, and for five minutes after the last one stops. A session
waiting for you keeps it awake for the first five minutes of the wait, not
all night.

With **closed-lid mode** on, that includes the lid: close your MacBook while
an agent works and it keeps running, until five minutes after the work
stops. Don't put it in a bag like that; it gets warm.

It's a rule like any other: let the display sleep, switch it off or delete
it in Settings → Keep Awake. It stops below your battery level too. Hidden
owlets still count. To leave one session out, right-click it and switch off
**Keep the Mac Awake While It Works**; that lasts until the session ends. A
session that says it's busy but has done nothing for two hours counts as
napping, so a forgotten one can't keep your Mac up.

### Hiding and muting

Right-click an owlet:

- **Hide → Until It Needs Me:** it comes back when it needs you or is stuck.
- **Hide → For Today.**
- **Hide → Always for "repository":** every session in that repository,
  except when one needs you.
- **Mute "repository":** its owlets still show, but never notify you and
  never appear in the island.

Settings → Agents → Hidden and muted lists hidden and muted repositories,
with **Show Again** and **Unmute**. Two kinds of session are hidden by
default:

- **Scripted sessions,** run from scripts, CI or the Agent SDK, such as
  `claude -p`.
- **Scratch folders:** temporary folders and the Claude app's scratch
  workspaces.

### The desktop widget

Add **Roost** from the widget gallery (right-click the desktop → Edit
Widgets, then search for Barn Owl). It comes small or medium: the Roost
under a glass dome, with owlets that are doing something on its branches,
nappers in the hollow and the ones home today in the nest, under a sky that
follows the time of day (or your Roost sky). Beside it, who needs you and
how many are busy, and the most useful line: what's being asked, what's
busy, or what came home. The medium one also shows your plan limits.

Click it to open the Roost; in the medium one, click an owlet to open the
Roost on it. Barn Owl updates the widget when something changes, about once
a minute at most when an owlet needs you and every five minutes otherwise,
as macOS allows widgets only so many updates. If it hasn't heard from Barn
Owl for 20 minutes, it says "As of" with the time. With Barn Owl closed or
coding agents off, the dome stands empty.

### Your week in the Roost

From Friday at 16:00 through Sunday, after a week with at least an hour of
agent work, the quick panel offers **Your week in the Roost**. It opens a
card with the week's hours of agent work, how many repositories and how long
you were needed, a few highlights (such as the most owlets at once or the
longest session), when the owlets flew (the night shift in amber), the
busiest repository, and any owl new to your field guide.

Repository names are hidden ("Tree A") every time it opens; choose **Shown**
to include them. Pick **Wide** for link previews or **Story** for a phone,
then **Copy Image**, **Save Image…** or **Share…**. The card holds only
times and counts, never anything from your prompts, code or branch names.

### Troubleshooting agents

**An owlet is missing.** Check Settings → Agents → On this Mac to see
whether Barn Owl found the agent. Then check it isn't hidden: **Hidden (2)**
in the quick panel shows hidden owlets, and scripted sessions and scratch
folders are hidden by default. Agents other than Claude Code are found by
their process every 15 seconds, or every minute when none have run for a
while, so a new one can take a moment. An agent started through a wrapper
with another name isn't recognised. If you've moved Claude Code's or Codex's
folder with `CLAUDE_CONFIG_DIR` or `CODEX_HOME` in your shell, Barn Owl,
which doesn't start from your shell, still looks in `~/.claude` and
`~/.codex`.

**Show doesn't pick the right tab.** Barn Owl can choose the tab in
Terminal and iTerm only; other apps just come to the front. Check that Barn
Owl may control them in System Settings → Privacy & Security → Automation.
Inside tmux or screen, the tab can't be told apart, so the app just comes to
the front.

**Plan limits say "as of".** The Claude app saves its usage history only now
and then, while it runs, so its readings are often older than half an hour.
Turn on Reset times for Claude for fresh numbers whenever a terminal session
is working. Codex's numbers arrive as Codex works.

**Reset times show nothing for sessions in the Claude app.** That's
expected: the Claude app's Code tab has no status line, so only Claude Code
in a terminal passes them on.

**Turn On… says something's wrong.** If Barn Owl isn't in Applications,
move it there first. If `~/.claude/settings.json` isn't valid JSON, Barn Owl
leaves it alone; fix it and try again.

**The island doesn't show.** Check Settings → Agents → Show at the notch,
and that you aren't presenting or in a full-screen app. It also stays away
when the session waiting for you is in the app in front, and for muted
repositories.

## Appearance

Settings → Appearance:

<img src="images/settings-appearance.png" alt="Settings → Appearance with the four owls to choose from" width="560">

- **Owl:** pick the owl's colours: Golden Barn, Ghost Owl, Ember or Moonlit
  Lilac. They apply to the owl in setup, panels and About; in the menu bar
  the owl takes the menu bar's colour.
- **Tint the menu bar** (off by default) with a colour or gradient, full width,
  as a rounded pill, or split around the notch, with an optional border and
  shadow.
- **Space between icons:** less space fits more icons beside the notch.
  Apps pick up the new spacing when they next start. **Apply to System Icons**
  restarts the system's own icons; log out and back in to apply it
  everywhere. **Reset to Default** goes back to macOS's spacing.

## The owl

The owl in the menu bar has its eyes open while your Mac is kept awake and
shut when it may sleep. It blinks now and then, its eyes follow your pointer
when you hover over it, it winks when you Option-click it, it wears shades
while you present, and its eyes droop in the last minute of a timed session.
When an icon pops into view because it changed, the owl glances at it, and
when an agent starts needing you, it glances at the owlet beside it.

Inside Barn Owl it has a life of its own:

- **Click it** for a hoot and a hop. Click three times quickly and it turns
  its head all the way round; keep clicking and it gets dizzy.
- **Press and hold** to pet it. In About, **grab it and throw it**.
- **Quick panel:** it stretches when keep-awake starts and yawns when it
  stops. It reacts to the toggles: glowing eyes for Dark Mode, "Shh!" for a
  muted microphone, "Peekaboo!" when the desktop hides. It wears a headset
  during calls, glasses at your desk, a blanket in closed-lid mode, and gets
  coffee the longer you stay up (two hours, five, then an all-nighter). It
  perks up when you plug in, and looks tired on a low battery.
- **The Nest:** it peeks over the tab, leans in when a file comes near, says
  "Nom!" if you drop one right on it, waves "Bye!" when a file leaves, and
  sweeps up when you clear it.
- **The Perch:** it sits on the corner and watches the icon you point at.
- **Search:** it watches the selected result and hops when exactly one thing
  matches. Try typing "hoot" or "dance".
- **Clipboard:** it covers its eyes when Barn Owl skips a password, and its
  chest turns the colour of a colour code you copy, like `#F5A633`.
- **Now and then:** it says good morning once a day, is livelier after
  midnight, nods off if you leave it alone (move the mouse to startle it),
  and dresses up for Halloween, December, New Year and its birthday. The
  dusk sky shows tonight's real moon.
- **In the Terminal:** `barnowl hoot`.

Settings → About shows how many of its moments you've met.

Settings → Appearance has its colours and its **personality**: *Lively* does
everything, *Calm* only reacts to what you do, and *Still* keeps it still.
With **Reduce Motion** on (System Settings → Accessibility → Display), it
keeps still too.

## Automation

### Shortcuts

Barn Owl adds these actions to the Shortcuts app: **Keep Mac Awake** (minutes),
**Stop Keeping Mac Awake**, **Set Presenter Mode**, **Show or Hide Menu Bar
Icons**, **Open Menu Bar Icon** (by app name) and **Show Clipboard History**.
Barn Owl needs to be running.

### Terminal

`barnowl` is installed by `Scripts/install.sh`, or download it from the release
page and move it to `/opt/homebrew/bin`.

```
barnowl show | hide | toggle | all       hidden icons
barnowl bar | search | clipboard         panels
barnowl awake [minutes|+minutes|stop]    keep awake (no minutes = until stopped)
barnowl present [on|off]                 presenter mode (no argument = toggle)
barnowl open <app>                       open an app's menu bar icon
barnowl place <app> visible|hidden|alwaysHidden
barnowl watch <app> [off]                show the icon when it changes
barnowl icon <app> <text>|reset          replace an app's icon with text or an emoji
barnowl settings [pane]                  open Settings
```

### Links

For Raycast, Alfred, scripts and anything that can open a URL:

| Link | Does |
|---|---|
| `barnowl://show`, `barnowl://hide`, `barnowl://toggle`, `barnowl://show-all` | Hidden icons |
| `barnowl://bar`, `barnowl://quick`, `barnowl://search`, `barnowl://clipboard`, `barnowl://nest`, `barnowl://barn` | Panels |
| `barnowl://keep-awake?minutes=60` (0 = indefinitely) | Keep awake |
| `barnowl://keep-awake/extend?minutes=30` | Add time |
| `barnowl://keep-awake/stop` | Stop |
| `barnowl://roost` | The Roost |
| `barnowl://roost?session=<id>` | The Roost, with one session picked (the widget's links use this; ids look like `claude:<session id>`) |
| `barnowl://presenter`, `?on=1`, `?on=0` | Presenter mode |
| `barnowl://open?app=Mail` | Open an app's icon |
| `barnowl://place?app=Mail&row=hidden` | Move an icon |
| `barnowl://watch?app=Mail` (`&on=0` to stop) | Show when it changes |
| `barnowl://icon?app=Mail&label=✉️` (`&reset=1` to undo) | Custom icon |
| `barnowl://settings?pane=layout` | Settings |
| `barnowl://setup` | The setup guide |

## Updates

The second time you open Barn Owl, it asks whether to check for updates
automatically. If you say yes, it checks once a day. When there's a new
version, it shows what's new and asks before installing; it restarts by
itself afterwards. To
check right away, use **Check for Updates…** in Settings → General, or the
arrow button at the bottom of the quick panel.

Switch off **Automatically check for updates** in Settings → General to only
check when you ask. The check downloads the list of releases from GitHub and
sends nothing about you or your Mac.

If you installed Barn Owl with Homebrew, it still updates itself;
`brew upgrade` leaves it alone.

## Troubleshooting

**The Perch or search says "Allow Accessibility".** Turn on Barn Owl in
System Settings → Privacy & Security → Accessibility. If it's already on,
switch it off and on again. That's sometimes needed after updating Barn Owl.

**Check for Updates… is greyed out.** Barn Owl is already checking, or an
update window is open. Look for it behind other windows.

**Hidden icons show app icons instead of their real pictures.** Allow
Screen Recording and relaunch Barn Owl, then use Layout → **Refresh Pictures**.

**My pointer moved by itself for a moment.** When Barn Owl moves an icon, it
uses the same ⌘-drag you would. It hides the pointer during the move and puts
it back afterwards. Moves happen when you arrange icons, open a hidden icon,
or when Barn Owl puts an icon back where it belongs. If it happens over and
over, please open an issue. Barn Owl gives up on an icon after two tries, so
it shouldn't happen.

**An icon won't stay where I put it.** Some apps re-create their icon when
they change state. Put it where you want in Layout; Barn Owl remembers it by
app and name.

**Uninstalling.** If you turned on answering from the island or Claude's
reset times, turn them off first in Settings → Agents, so Claude Code's
settings are as they were. (If you forget, no harm is done: the commands do
nothing once Barn Owl is gone.) Then quit Barn Owl (quick panel → power
button) and move it to the Trash. Its settings are in
`~/Library/Preferences/io.github.marvika.BarnOwl.plist`, and its pictures,
clipboard history and agent records are in
`~/Library/Application Support/Barn Owl`. The widget's snapshot is in
`~/Library/Group Containers/2S5J2CYWPZ.io.github.marvika.BarnOwl`, and the
backup of Claude Code's settings, if Barn Owl made one, is
`~/.claude/settings.json.barnowl-backup`. Remove Barn Owl from Accessibility,
Screen Recording and Automation in Privacy & Security.
