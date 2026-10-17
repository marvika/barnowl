# Roadmap

## v0.1: MVP (done)

- Hidden and always-hidden sections, auto-rehide, global hotkeys
- macOS 26 length engine and macOS 27 native-visibility engine (27 untested)
- Keep awake: timed, indefinite, while an app runs; display sleep option
- Quick toggles: dark mode, desktop icons, hidden files
- Guided setup, sidebar Settings, launch at login, `barkeep://` URL scheme

## v0.2: See and reach every icon

- Inventory of all items (Accessibility, matched to windows on macOS 26,
  where Control Center owns every item window)
- **Barkeep Bar**: a dropdown panel under the menu bar with images of hidden
  icons (Screen Recording), click-through to the real item
- **Notch overflow**: detect icons stuck behind the notch and show them in the
  Barkeep Bar automatically
- **Search**: hotkey palette over every menu bar item
- Layout editor in Settings: drag icons between sections instead of ⌘-dragging
- macOS 27: place Barkeep's own items with a ⌘-drag of its own icon on first
  run (27 ignores Preferred Position)

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
