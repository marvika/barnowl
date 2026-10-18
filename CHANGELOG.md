# Changelog

All notable changes to Barn Owl. Versions follow [semantic versioning](https://semver.org);
before 1.0, a minor version can change behaviour.

## 0.10.2

- Closed-lid mode stays on through updates, and through restarts when Barn
  Owl opens at login, instead of switching off (and asking for your password
  in the middle of shutting down). Quitting Barn Owl still turns it off.

## 0.10.1

- Lighter on your Mac: Barn Owl no longer hears every pointer movement
  unless you've turned on showing hidden icons by hovering or scrolling
  (that alone cost a few percent CPU whenever the mouse moved), and the
  Barn's map of the disk is let go two minutes after you close the Barn.

## 0.10.0

- **A fresher look.** Floating panels share one Liquid Glass style with a
  touch of dusk, and the owl's lavender is the accent everywhere. The quick
  panel puts the owl and a big countdown first, has one row of time buttons
  and round Control Center–style toggles. Search groups commands and icons
  and shows what Return does. Toggles bounce, icons settle onto the Perch,
  the Nest glows as a file comes near, and the app icon is a layered Liquid
  Glass icon with dark and tinted versions. Sizes read the same everywhere.
- Clearing clipboard history or the Nest asks first. New links:
  `barnowl://quick` and `barnowl://nest`.
- **The Barn**, for disk space: a storage bar that adds up to the whole
  disk, and Tidy Up, sorted by how safe things are. Safe caches and build
  files go in one click; macOS installers, apps you haven't opened in six
  months, big old downloads and app caches are yours to pick, go to the
  Trash with Undo, and can be emptied from it on their own. Each clean-up is
  locked to its own folders, waits while its app or a build is running, and
  asks before anything that can't be undone. Explore draws a ring map of the
  disk with the biggest files by kind, Quick Look and a basket for the
  Trash. It warns when the disk is nearly full, and never cleans by itself.
- Barn Owl no longer uses CPU while idle: closed panels are torn down and
  hidden owls stop.

## 0.9.1

- The owl's speech bubble stays inside its window and no longer covers the
  text next to the owl: the step titles in setup, "Keep Awake" in the quick
  panel, or the edge of the Perch.
- `barnowl awake 2h` keeps the Mac awake for two hours instead of
  indefinitely, and search reads "awake 2 h" as two hours.
- `barnowl show` only shows hidden icons; it no longer hides them when
  they're already showing.
- Overnight keep-awake schedules, such as weeknights 22:00–02:00, count
  from the night they start.
- Turning presenter mode off during a screen share keeps it off until the
  share ends.
- Changing displays while presenting no longer brings hidden icons back.
- Quitting with closed-lid mode on also clears its setting.
- Pinned images no longer come back empty after a restart.
- The clipboard panel keeps the right entry selected when the list changes,
  and pastes into your app when opened from search or Settings.
- One panel at a time: opening the quick panel, the clipboard, search or
  Settings closes the Perch (and the other way round), instead of leaving it
  open underneath.
- The Nest's tab under the notch keeps up when you add, remove or clear files
  from the clipboard panel's Nest tab.
- After a session stops for low battery, plugging in clears "Stopped: battery
  low" from the status.
- When presenting ends, desktop icons you showed again by hand stay showing.
- **Keep me available** pauses while the display may sleep, so the display can
  still sleep and your Mac can still lock.

## 0.9.0

- **Hide Desktop** now covers the desktop with a picture of your wallpaper
  instead of restarting Finder, so icons come back exactly where they were
  and Finder windows stay open.
- **Hidden Files** lets Finder quit properly before reopening it, so it keeps
  its windows and icon positions.
- The quick panel no longer closes when Barn Owl moves icons, for example
  when you start presenting.
- When presenting starts, the owl says "Incognito!" instead of "Wide awake!".
- **The owl everywhere:** it reacts to the quick toggles, dresses for what's
  going on (a headset in calls, glasses at your desk, a blanket in closed-lid
  mode, coffee on long sessions), perks up when you plug in, perches on the
  Perch, peeks over the Nest's tab and waves files goodbye, follows search
  results, and covers its eyes when you copy a password.
- **Menu bar owl:** its eyes follow your pointer, it winks on Option-click,
  wears shades while presenting, droops in a session's last minute, glances
  at icons that pop into view, and blinks awake with your Mac.
- **Surprises:** good morning once a day, a livelier night owl, Halloween,
  New Year and birthday outfits, tonight's real moon in the sky, a throwable
  owl in About, and `barnowl hoot` in the Terminal.
- **Owl personality** in Settings → Appearance: Lively, Calm or Still.
- **A collection** in Settings → About: 38 owl moments to meet.
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
