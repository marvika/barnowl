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

## Later

- Notarization and automatic updates (need a Developer ID certificate)
- Test on macOS 27 and place Barn Owl's own icons there
- Verify display profiles and closed-lid mode on real hardware
