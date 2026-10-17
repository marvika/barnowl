# Changelog

All notable changes to Barn Owl. Versions follow [semantic versioning](https://semver.org);
before 1.0, a minor version can change behaviour.

## Unreleased

- **Hide Desktop** now covers the desktop with a picture of your wallpaper
  instead of restarting Finder, so icons come back exactly where they were
  and Finder windows stay open.
- **Hidden Files** lets Finder quit properly before reopening it, so it keeps
  its windows and icon positions.
- The quick panel no longer closes when Barn Owl moves icons, for example
  when you start presenting.
- When presenting starts, the owl says "Incognito!" instead of "Wide awake!".
- The docs say macOS 26 *and later*: Barn Owl runs on macOS 27 too.

## 0.8.0

- Barn Owl can update itself. On the second launch it asks whether to check
  automatically (once a day), and it always asks before installing. Change
  that or check right away in Settings → General, or use the new button at
  the bottom of the quick panel.
- The Homebrew cask is marked as updating itself, so `brew upgrade` leaves it
  alone.
- Clicking an owl in Settings → Appearance now always switches its colours.
  Before, a click on the owl itself was sometimes ignored.

## 0.7.1

- Files leave the Nest once you drag them out and drop them somewhere. An
  option in Settings → Clipboard keeps them instead.
- **Drag all** takes every file in the Nest at once.
- Files moved or deleted elsewhere leave the Nest by themselves.
- The clipboard panel's Shelf tab is now called the Nest.
- A Homebrew cask (`Casks/barn-owl.rb`), and the `barnowl` command now ships
  inside the app so Homebrew can link it.

## 0.7.0

Barkeep is now **Barn Owl**. Settings, layout, groups and clipboard history
carry over on first launch.

- A mascot: an owl that watches your pointer, hoots, hops, turns its head,
  gets dizzy, loves being petted, yawns, nods off, wears shades while you
  present and celebrates the end of setup.
- Owl colours in Settings → Appearance: Golden Barn, Ghost Owl, Ember and
  Moonlit Lilac.
- New app icon and menu bar icon.
- The drop tray is the **Nest**; the strip of hidden icons is the **Perch**.
- Releases are signed and notarized, so there's no "Open Anyway" step.

## 0.6.0

- The time left in a keep-awake session shows in the menu bar, with quick
  buttons to add time.
- A drop tray under the notch appears while you drag files.
- Fixed a loop that could keep moving grouped icons and the pointer.

## 0.5.0

- Search runs commands as well as finding icons: `awake 2h`, `dark`,
  `present` and more.
- Clipboard history with pinning, and a shelf for files.
- Replace any app's menu bar icon with a symbol, emoji or text.
- `Scripts/install.sh` and the `barnowl` command.

## 0.4.0

- Show when it changes: hidden icons pop into view when they change.
- Presenter mode hides icons while you share your screen.
- A separate layout while an external display is connected.

## 0.3.0

- Layout editor: drag icons between the menu bar, Hidden, Always hidden and
  groups.
- Groups: one menu bar icon that opens several.
- Icons stay where you put them when apps restart.
- Keep-awake rules, the quick panel and closed-lid mode.

## 0.2.0

- A strip under the menu bar for hidden icons, including those stuck behind
  the notch.
- Search the menu bar.

## 0.1.0

- Hide menu bar icons behind an arrow.
- Keep your Mac awake, and quick toggles.
