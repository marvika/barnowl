# How Barn Owl works

Barn Owl is a Swift app (AppKit plus SwiftUI) for macOS 26 and later. It isn't sandboxed
and can't be on the App Store: reading other apps' menu bar items needs
Accessibility, and the macOS 27 engine uses a private API.

## Project layout

| Folder | What's there |
|---|---|
| `BarnOwl/App` | App delegate, the shared `AppModel`, `barnowl://` link handling |
| `BarnOwl/MenuBar` | Status items, sections, hiding engines, item scanning, moving and opening icons |
| `BarnOwl/Layout` | The layout editor and `LayoutController`, which remembers and restores icon positions |
| `BarnOwl/Groups` | Groups and custom icons |
| `BarnOwl/Context` | Show when it changes, presenter mode |
| `BarnOwl/KeepAwake` | Sessions, rules, closed-lid mode |
| `BarnOwl/Clipboard` | Clipboard history, shelf and drop tray |
| `BarnOwl/Roost` | Coding agents: reading their sessions, the owlets, the Roost, the island, plan limits, the daily log and the recap |
| `BarnOwlWidget` | The desktop widget, a separate sandboxed extension |
| `BarnOwl/Search`, `QuickPanel`, `Barn OwlBar`, `Settings`, `Onboarding`, `Appearance` | The panels and windows |
| `BarnOwl/Automation` | Shortcuts actions |
| `BarnOwlTests` | Unit tests for the logic that doesn't need a real menu bar |
| `Scripts` | `install.sh`, `demo.sh`, the `barnowl` command, icon and hero image generators |

The Xcode project is generated from `project.yml` with XcodeGen.

## Hiding

Barn Owl owns three status items: the **arrow**, a `|` **divider**, and an
optional `⋮` **always-hidden divider**.

- **macOS 26** (`LengthEngine`): to hide, the divider's width grows to about
  the screen's width, which pushes everything left of it past the left edge.
  This needs no permissions. On first launch Barn Owl seeds
  `NSStatusItem Preferred Position` so the arrow sits next to Control Center,
  never behind the notch.
- **macOS 27** (`NativeVisibilityEngine`, untested): macOS drops over-wide
  status items, so Barn Owl reads which apps sit left of the divider and asks
  macOS to show only the others, through `MenuBarClientCore`'s
  assessment-mode restriction (found by Hidden Bar). Hiding is per app there,
  and system items always stay.

Both sit behind the `HidingEngine` protocol, so a future macOS only needs a
new engine.

## Finding icons

On macOS 26 every menu bar item's window belongs to Control Center, so the
window list can't say which app an icon belongs to. `ItemScanner` reads each
app's `AXExtrasMenuBar` items through Accessibility, and matches them to the
status windows by horizontal position, within 4 pt. Barn Owl's own windows are
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
windows, so its background is transparent. Barn Owl crops it into one picture
per icon and saves them to `~/Library/Application Support/Barn Owl/Icons`.
**Refresh Pictures** briefly moves icons that have no picture into view.

## Moving icons

`ItemMover` moves any icon with a synthetic ⌘-drag, the way Frost does:

1. A ⌘ mouse-down is posted **on Barn Owl's own arrow**, with event field
   `0x33` set to the target icon's window ID. macOS routes the event by that
   field and lifts the target icon, even an off-screen one.
2. Barn Owl waits until the icon has lifted (20–60 ms).
3. It posts the mouse-up next to the destination, then checks the result and
   retries up to three times.

Another app's icon is never clicked. The pointer is hidden during the move
and put back afterwards. "Left of the arrow" is unreliable, because the
lifted icon's slot is reserved where the mouse-down lands. So Barn Owl's
destinations are relative to the dividers, or right of a group or custom
icon.

## Opening a hidden icon

A hidden icon ignores presses, because its menu would open off screen.
`ItemOpener` moves it next to the icon you clicked, presses it through
Accessibility, and moves it back once its menu closes. Apps busy opening
their menu often answer the press with "cannot complete" even though it
worked, so Barn Owl checks for a menu window before falling back to a real
click.

## Keeping icons in place

`LayoutKeeper` (pure, tested) compares each scan with the saved layout:

- a key with a **new window** in the wrong row means the app re-added its
  icon, so Barn Owl moves it back;
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
describes itself as "Control Center, Screen Recording is in use". Barn Owl
reads that through Accessibility. Barn Owl's own picture taking lights up the
same indicator, so it ignores the 10 seconds after its own captures and needs
two readings in a row. Presenting moves the visible icons into the hidden
section without changing the saved layout, and restores them in order
afterwards.

## Keep awake

`KeepAwakeController` holds one `IOPMAssertion`, the same mechanism as
`caffeinate` and Amphetamine. It's held while either a session or an active
rule wants it, and it's display-sleep or system-sleep depending on the
options; of the rules that hold, one that keeps the screen on wins. Rules are
checked every 15 seconds and when apps, displays or power change. Power and
battery come from IOKit, the microphone from CoreAudio
(`kAudioDevicePropertyDeviceIsRunningSomewhere`, no permission needed), and
downloads from unfinished files in ~/Downloads. That last one is only read
when a rule or session uses it. Closed-lid mode asks the power manager
(`IOPMrootDomain`, `kPMSetClamshellSleepState`) not to sleep when the lid
closes, only while keep awake is on, as Amphetamine does. That needs no
password and no helper.

## Clipboard and drop tray

`ClipboardHistory` polls the pasteboard's change count twice a second. It
skips anything marked concealed or transient (nspasteboard.org) and copies
made in known password managers. The drop tray watches global mouse drags. A
drag that changes the drag pasteboard with file URLs is a file drag, so the
tray slides out under the notch.

## Coding agents

`AgentWatcher` (on the main thread) turns sessions into owlets, and
`AgentReader` (an actor) does all the file and process work off the main
thread. With the feature off, neither runs: no timers, no folder watchers,
no process scans.

### What it reads

- **Claude Code** writes one small file per running session to
  `~/.claude/sessions/<pid>.json`, whether it runs in a terminal, the Claude
  app's Code tab or the Agent SDK: the session ID, folder, name, how it was
  started, and its status (busy, idle, or waiting and why). The `.key`
  files beside them are never opened. A file only counts while its process
  is alive and started when the file says, because a crashed session leaves
  its file behind and macOS reuses PIDs.
- Each session's log, `~/.claude/projects/<folder>/<session>.jsonl`, is
  followed from where the last read stopped: the first read takes the last
  256 KB, later ones only what was added, at most 8 MB at a time. Each line
  is decoded in memory and only these are kept: tool names, whether a
  command failed, when a turn started and ended, the branch, API errors
  (rate limit, network), pull request links, and the input of a call that's
  waiting for you (the command, the question and its options, the file, the
  address), until it's answered. Commands are sorted into tests, builds and
  git, in memory, to say what failed. Lines over 128 KB, which are tool
  results, are only scanned for their call ID and error flag.
- A session's helpers come from `<session>/subagents/*.meta.json` (their
  type and task) and how recently their logs changed.
- For sessions started in the **Claude app**, its records in
  `~/Library/Application Support/Claude/claude-code-sessions/` give the
  chat's ID and title. Only the first 4 KB of each are read, and they're
  looked for at most every 30 seconds while one is missing. Show opens
  `claude://code/continue?session=local_…`.
- **Codex** logs to `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`. A running
  `codex` is matched to the newest log for its folder written since it
  started. Only event types, tool names, exit codes, timing and the
  `rate_limits` it reports are used.
- **Mistral Vibe** 3 keeps each session in
  `~/.vibe/logs/session/unified/<id>/`. A running Vibe holds a lease on its
  session in `active/<id>.lock.json`, naming the app server that `vibe-rs`
  starts as its child, so each `vibe-rs` is matched to the lease whose
  process is its child (or itself, when an editor hosts Vibe through
  `vibe-acp`). The lease is read on every look, since `/clear` starts a new
  session in the same process. Barn Owl follows the session's journal
  (`journal/<sequence>.jsonl`), which Vibe appends to during a turn and
  starts afresh after it, and uses only the session's state, its tools'
  names and outcomes, open approvals and questions, and the turn's timing;
  the title comes from `meta.json`.
- `CLAUDE_CONFIG_DIR`, `CODEX_HOME` and `VIBE_HOME` are respected when
  they're set in Barn Owl's own environment.

Prompts, replies, command output, logins, tokens, cookies and environment
variables are never read or kept.

### How often

`~/.claude/sessions` is watched with a `DispatchSource`, so a session that
starts or ends is read 0.3 seconds later, and each Claude Code process has an
exit source. Besides that, Barn Owl looks every 2 seconds while any agent
works or waits for you, every 5 while sessions sit idle, and every 30 with
none. A new state must hold for 1.5 seconds before an owlet changes pose, so
quick tool calls don't make it flicker; "needs you" shows at once.

Drawing costs nothing when you can't see it. The Roost and tree windows let
go of their views when closed, and owlets hold still while a window is
hidden behind others, with Reduce Motion or Still, and in Low Power Mode.
The tree's sky and branches are painted once per size, light and set of
branches; only the owlets move.

### Other agents

`ProcessScan` finds agents other than Claude Code with libproc, the calls
Activity Monitor uses, for your own processes only and with no permission:
`proc_listallpids`, then `proc_pidinfo` with `PROC_PIDTBSDINFO` (name, owner,
parent, start time, terminal), `PROC_PIDVNODEPATHINFO` (working folder) and
`PROC_PIDTASKINFO` (CPU time). Native agents are known by name (`codex`,
`vibe-rs`, `opencode`, `copilot`, `gemini`, `cursor-agent`, `droid`, `goose`,
`crush`, `aider`, `amp`). A run for one prompt (`vibe -p …`, `codex exec …`)
counts as scripted, unless another agent started it: each agent's parent
processes are looked up once, and the nearest that's a Claude Code session or
another agent is its caller. For `node`, `bun` and `python`, the first few arguments say
which script runs; they're read with `sysctl(KERN_PROCARGS2)`, and the
environment that follows them never is. Editors' background servers
(`app-server`, `mcp-server`…) are skipped, and only the outermost process of
an agent counts.

The scan runs every 15 seconds at most, and every 60 once four scans in a
row found nothing. An agent with no log to read counts as working while it
used at least 2% of a core since the last scan.

The app a session runs in is found by walking up its parents to the first
regular app. In Terminal and iTerm, Show finds the session's terminal device
(`/dev/ttys003`) and runs a short AppleScript through `osascript` that
selects the tab with that device; macOS asks once for Automation. The
repository comes from the folder's `.git` (a worktree's `.git` file points
at its main repository) or a `.claude/worktrees/`, `.worktrees/` or
`.codex/worktrees/` path.

### Plan limits and the status line relay

Claude's limits come from `~/Library/Application Support/Claude/plan-usage-history.json`,
reread only when it changes. Its newest weekly reading counts for up to a
week, its 5-hour one for up to five hours; a forecast comes from the last
day's readings. Codex's come from the `rate_limits` in its logs and are kept
for six hours.

With the relay on, Claude Code's `statusLine` command is
`b='…/Barn Owl'; [ -x "$b" ] && exec "$b" --statusline -- 'original'; original`.
`main.swift` checks for `--statusline` before anything else, so the app never
starts. Barn Owl reads the status JSON from standard input, saves only
`rate_limits.five_hour` and `rate_limits.seven_day` (`used_percentage` and
`resets_at`) to `~/Library/Application Support/Barn Owl/claude-limits.json`,
puts the input back on standard input through a temporary file (readable
only by you, deleted at once) and `exec`s `/bin/sh -c original`. Your
command, quoted inside the relay's, still runs if Barn Owl is gone. Readings
older than six hours, or past their reset, are ignored. Turning it on saves
the old setting to `statusline-original.json`; turning it off puts it back
and deletes both files.

### Answering from the island

Turning it on adds two hooks to `~/.claude/settings.json`:
`PermissionRequest` with matcher `*`, and `PreToolUse` with matcher
`AskUserQuestion`. Both run
`b='…/Barn Owl'; [ -x "$b" ] && exec "$b" --answer; :`, with a timeout of
615 seconds.

1. **Is Barn Owl there?** While answering is on, the app holds an exclusive
   `flock` on `~/Library/Application Support/Barn Owl/answers/listening`.
   The hook (`Barn Owl --answer`, which never starts the app) tries a shared
   lock without waiting: if it gets one, nobody is listening, so it prints
   nothing and Claude Code shows its usual prompt. The system lets go of the
   lock the moment Barn Owl quits or crashes, so a hook never waits for an
   app that isn't there.
2. **The request.** The hook reads Claude Code's input from standard input
   and writes `answers/<uuid>.ask`: the session ID, its own PID, the tool,
   the time, the text (the command, file, address, pattern, path or query;
   for any other tool, its name and every argument), a question's options,
   and what Claude Code's suggested "always allow" rule would cover. The
   folder is readable only by you (0700), and so is each file (0600).
   Questions with several parts or multiple choice aren't written; they go
   to the usual prompt.
3. **The island.** Barn Owl watches the folder and matches the request to
   its session. It answers "pass" straight away when the island can't show
   it, the session is hidden or muted, you're in that session's app, or the
   session has moved on; and for a request no session claims within three
   seconds.
4. **Your answer.** A click writes `answers/<uuid>.reply` (0600): allow,
   deny, always, an option's label, or pass. The hook looks every 0.1
   seconds, checks the lock every 2, and gives up after ten minutes.
5. **The hook's output,** as Claude Code's hooks reference describes it:
   for a permission, `allow`, `deny` (with "Denied from Barn Owl's island."),
   or `allow` with `updatedPermissions` set to Claude Code's own suggestions
   that allow something; for a question, `permissionDecision: allow` with the
   chosen label as its answer, only if it's one of the options. A pass, or
   anything unexpected, prints nothing, so the usual prompt appears. The
   hook deletes both files as it exits, and Barn Owl clears leftovers whose
   hook is gone.

Both features write the real file behind a symlink, keep its permissions,
and leave an unreadable file alone. Before the first change, a copy is saved
as `settings.json.barnowl-backup` (0600), once. After an update or a move,
Barn Owl points its hooks and relay at the copy that's running.

### The widget

`WidgetFeed` writes a small snapshot, `roost.json`, to the app group folder
the app shares with the widget,
`~/Library/Group Containers/2S5J2CYWPZ.io.github.marvika.BarnOwl`: up to 12
owlets (name, repository, state, colour, and the question or command one is
waiting on), up to four plan windows, today's working time, and counts.
WidgetKit allows only so many reloads a day, so Barn Owl reloads the widget
when what it shows changes, a minute apart at most when something needs you
and five otherwise, and otherwise rewrites the file every ten minutes so the
widget can tell a quiet hour from Barn Owl having stopped. After 20 minutes
without word, the widget says "As of". On quit, or with the feature off, the
snapshot becomes an empty one. The widget runs in the App Sandbox and reads
only that file.

### The daily log and keep awake

`DailyLog` keeps each day's totals in
`~/Library/Application Support/Barn Owl/daily-log.json` for 60 days, for the
Roost's Today card and the weekly recap: working and waiting time, time per
hour and per repository name, the most at once, the longest session, pull
requests and how long each wait lasted. Today's sessions are kept by a hash
of their ID, never the ID. It's saved now and then, and on quit. The flight
log is kept in memory only.

The keep-awake condition "an agent is working" holds while an agent you
haven't left out works, or started waiting for you, less than five minutes
ago, measured by uptime so a clock change can't stretch it. Keep awake looks
again when that changes, and its 15-second check notices the five minutes
running out.

## Demo mode

`Scripts/demo.sh` runs a copy of Barn Owl with its own bundle ID and settings,
and with `BarnOwlDemo` set. Demo mode shows made-up icons, clipboard entries,
shelf files and owlets, and never reads, moves or saves anything real; it
doesn't update the desktop widget either. The
screenshots in this repository come from it.
