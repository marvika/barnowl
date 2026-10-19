# Roadmap

## v0.1: MVP (done)

- Hidden and always-hidden sections, auto-rehide, global hotkeys
- macOS 26 length engine and macOS 27 native-visibility engine (27 untested)
- Keep awake: timed, indefinite, while an app runs; display sleep option
- Quick toggles: dark mode, desktop icons, hidden files
- Guided setup, sidebar Settings, launch at login, `barnowl://` URL scheme

## v0.2: See and reach every icon (done)

- Item inventory: Accessibility items matched to windows (Control Center owns
  every item window on macOS 26)
- Perch: hidden and behind-the-notch icons in a strip under the menu
  bar, with real pictures (Screen Recording) and click-through
- Notch detection, plus an Automatic / In the menu bar / On the Perch
  setting
- Search palette (⌃⌥⌘M)
- `barnowl://open?app=…`, `barnowl://bar` and `barnowl://search`
- Setup step and Settings rows for where icons appear and for permissions

## v0.3: Arrange, groups and keep awake (done)

- Layout editor with drag and drop; programmatic icon moves
- Groups with their own menu bar icon and dropdown
- Layout memory: icons go back where they belong after relaunches; new-icon
  placement setting; Battery and Wi‑Fi visible by default
- Pictures saved to disk, and a refresh for icons behind the notch
- Keep awake: sessions until a time / while downloading, rules (power,
  external display, microphone, downloads, apps, schedule), battery stop,
  keep me available, notifications, closed-lid mode
- Quick panel with toggle tiles (dark mode, microphone, desktop, hidden
  files, sleep display) from the owl icon

Still to verify: closed-lid mode (needs an admin password), click fallback for
Electron apps such as Docker Desktop, everything on macOS 27.

## v0.4: Context (done)

- Show on change: status text, width and re-added icons every 3 s; picture
  comparison after network changes or on an opt-in interval
- Presenter mode: automatic while screen sharing or recording, manual tile and
  shortcut; keeps awake; optional desktop-icon hiding
- Display profiles: separate laptop and desk layouts, switched on dock/undock

Still to verify: display profiles with a real external display.

## v0.5: Extras (done)

- Commands in search ("awake 2h", "dark", "present", "arrange"…)
- Hover over the arrow or scroll over the menu bar to reveal (optional)
- Menu bar tint and shapes (optional, off by default) and icon spacing
- Custom icons for other apps' items (one-icon groups that open directly)
- Clipboard history (password-manager safe) and a drag-and-drop shelf
- Shortcuts actions, a `barnowl` command and more `barnowl://` links
- App icon and `Scripts/install.sh` (Release build in /Applications)

## v0.12: The Roost (done)

- Coding agents as owlets: Claude Code (terminal, the Claude app's Code tab,
  the Agent SDK) and Codex from their own session files; Copilot CLI,
  OpenCode, Gemini CLI and others from a libproc process scan
- An owlet beside the owl in the menu bar, and an Owlets card in the quick
  panel with the one that needs you and plan limits as moons
- The Roost window: Now (needs you, working, done, napping, today, by repo,
  flight log) and Tree (a branch per repository, a sky that follows the time
  of day), with a pop-out tree that can stay on top
- Show and Answer go to the exact Terminal or iTerm tab, or the exact chat in
  the Claude app
- The island at the notch, and answering Claude Code from it through its
  hooks (opt-in)
- Notifications only when the island can't show it or you're away
- Plan limits from the Claude app's usage history and Codex's logs, with
  Claude's reset times from an opt-in status line relay
- Keep awake while an agent is working, as a rule
- A desktop widget and a weekly recap card
- Settings → General → Features, to turn whole features off

## Later

- Test on macOS 27 and place Barn Owl's own icons there
- Verify display profiles and closed-lid mode on real hardware
