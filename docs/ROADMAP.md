# Roadmap

## v0.1: MVP (done)

- Hidden and always-hidden sections, auto-rehide, global hotkeys
- macOS 26 length engine and macOS 27 native-visibility engine (27 untested)
- Keep awake: timed, indefinite, while an app runs; display sleep option
- Quick toggles: dark mode, desktop icons, hidden files
- Guided setup, sidebar Settings, launch at login, `barkeep://` URL scheme

## v0.2: See and reach every icon (done)

- Item inventory: Accessibility items matched to windows (Control Center owns
  every item window on macOS 26)
- Barkeep Bar: hidden and behind-the-notch icons in a strip under the menu
  bar, with real pictures (Screen Recording) and click-through
- Notch detection, plus an Automatic / In the menu bar / In the Barkeep Bar
  setting
- Search palette (⌃⌥⌘M)
- `barkeep://open?app=…`, `barkeep://bar` and `barkeep://search`
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
  files, sleep display) from a cup icon

Still to verify: closed-lid mode (needs an admin password), click fallback for
Electron apps such as Docker Desktop, everything on macOS 27.

## v0.4: Context

- **Show on change**: surface a hidden icon for a while when its image changes
  (VPN drops, sync errors, security agent alerts)
- **Profiles by display**: tight layout on the laptop screen, roomier with an
  external display
- **Presenter mode**: hide everything while screen sharing or on camera

## v0.5: Extras

- Menu bar styling (tint, shapes, borders) and icon spacing
- Custom icons for other apps' items; per-icon hotkeys
- Hover or scroll to reveal hidden icons
- Commands in search ("awake 2h", "dark")
- Clipboard history and drag-and-drop shelf
- Shortcuts actions (App Intents) and a CLI
- App icon, Release build, Sparkle updates, notarization
