# Security

Barn Owl has Accessibility and Screen Recording access, reads your
clipboard and your coding agents' session files, and can answer Claude
Code's permission prompts when you ask it to, so security reports matter.

## Supported versions

Only the [latest release](https://github.com/marvika/barnowl/releases/latest)
gets fixes.

## Reporting a vulnerability

Please don't open a public issue. Report it privately through
**Security → Report a vulnerability** on this repository, or contact the
maintainer, [@marvika](https://github.com/marvika). You'll get a reply within
a week.

## What Barn Owl does with your data

- It works entirely on your Mac: no accounts or analytics. Its only network
  request is checking GitHub for new versions: it downloads `appcast.xml` from
  this repository and sends nothing about you or your Mac. Automatic checks can
  be switched off in Settings → General.
- Updates are signed twice: with the maintainer's Developer ID and with an
  EdDSA key only the maintainer holds. Sparkle installs an update only when
  both match.
- Clipboard history skips copies marked private and known password managers,
  and never saves images to disk.
- Settings live in `~/Library/Preferences/io.github.marvika.BarnOwl.plist`;
  icon pictures and clipboard history in `~/Library/Application Support/Barn Owl`.

### Coding agents

With coding agents on (Settings → General → Features), Barn Owl reads, and
never changes:

- Claude Code's session files in `~/.claude/sessions` (never the `.key` files
  beside them), each session's log in `~/.claude/projects`, and its helpers'
  descriptions;
- Codex's session logs in `~/.codex/sessions`;
- Mistral Vibe's session store in `~/.vibe/logs/session`: which process holds
  each session, and each session's title and journal;
- the Claude app's records of its Code-tab sessions (the first 4 KB of each,
  for the chat's ID and title) and its plan usage history, both in
  `~/Library/Application Support/Claude`;
- your own processes' names, folders, start times, CPU time and arguments,
  through libproc; never their environment.

It shows each session's title, state, folder and branch and, while one waits
for you, the command, file or question it's asking. It never keeps your
prompts, replies or command output, never reads logins, tokens or cookies,
never asks a server for anything, and sends nothing anywhere.

It writes:

- `~/Library/Application Support/Barn Owl/daily-log.json`: each day's times,
  counts and repository names, for 60 days. Today's sessions are kept by a
  hash of their ID.
- `~/Library/Application Support/Barn Owl/claude-limits.json`: with Claude's
  reset times on, the two plan windows' percentages and reset times, and
  `statusline-original.json`, your status line setting from before.
- `~/Library/Application Support/Barn Owl/answers/`: with answering from the
  island on, one small file per request while it waits for your answer, and
  your answer, deleted once it's given. The folder is readable only by you.
- `~/Library/Group Containers/2S5J2CYWPZ.io.github.marvika.BarnOwl/roost.json`:
  the desktop widget's snapshot (session names, repositories, states, the
  question or command one is waiting on, and plan limits). The widget runs
  in the App Sandbox and reads only this file.
- `~/.claude/settings.json`, only when you turn on answering from the island
  or Claude's reset times, after showing you the exact change. A copy of the
  file from before Barn Owl first changed it is saved once, beside it, as
  `settings.json.barnowl-backup`, readable only by you. Turning either
  feature off removes Barn Owl's entries.

Answering from the island never allows anything without your click, and its
"always allow" adds only the rule Claude Code itself suggests. Each request
waits only while Barn Owl holds a lock that the system releases the moment
Barn Owl quits or crashes; otherwise Claude Code shows its usual prompt.
[How it works](docs/how-it-works.md#answering-from-the-island) describes the
protocol.
