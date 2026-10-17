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

Still to do from v0.2:

- Verify the click fallback for apps that ignore Accessibility presses
  (often Electron apps, such as Docker Desktop)
- Layout editor in Settings: drag icons between sections instead of ⌘-dragging
- macOS 27: place Barkeep's own items with a ⌘-drag of its own icon on first
  run (27 ignores Preferred Position), and test the native engine and the
  Barkeep Bar there
- Disk cache for item pictures, so they survive a relaunch without one
  expansion

## v0.3: Context

- **Show on change**: surface a hidden icon for a while when its image changes
  (VPN drops, sync errors, security agent alerts)
- **Groups**: one icon that opens a small group, e.g. "Work" (VPN, security
  agents, device management) and "Dev" (Docker, Claude)
- **Profiles by display**: tight layout on the laptop screen, roomier with an
  external display
- **Presenter mode**: hide everything while screen sharing or on camera

## v0.4: Keep awake rules and extras

- Rules: on power with an external display; during calls; while downloading or
  copying; while a process (build, Docker) runs; battery threshold to stop
- **Closed-lid mode** via a privileged helper (`pmset disablesleep`), with
  battery and temperature safeguards
- Clipboard history and drag-and-drop shelf
- Shortcuts actions (App Intents) and a CLI
