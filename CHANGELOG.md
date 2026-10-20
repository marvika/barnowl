# Changelog

All notable changes to Barn Owl. Versions follow [semantic versioning](https://semver.org);
before 1.0, a minor version can change behaviour.

## Unreleased

- **Mistral Vibe gets an owlet.** Vibe 3 sessions show what they're doing,
  from Vibe's own session store: thinking, running a command, editing,
  searching, on the web, waiting for its helpers, fixing after failed
  commands, paused for a rate limit, done after a long turn, and when it
  wants your OK or has a question, with the command or question itself.
  The owlet takes the session's title, and follows `/clear` into the new
  session. Vibe's owlets are ember.
- A new Vibe shows up the moment it starts, not at the next look for
  processes.
- **Agents that call other agents.** When an agent starts another (Claude
  Code running `vibe -p …` or `codex exec …` for a second opinion or a piece
  of work), the helper perches with its caller: on a twig that grows out of
  the caller's branch, named for its model and what it's doing ("Devstral
  Medium · Running a command"), under one label that says who asked and how
  many are working and back. Past five, the rest huddle as a flock with "+N".
  Picking the caller lists all its helpers in the inspector; the Now view
  shows "3 of 10 back" on the caller's row; the quick panel counts them in
  its line; and a helper that needs you says who it's working for. Helpers
  are shown even though they run from a script. A session that's waiting
  for its helpers stays on its branch, though its agent reports itself idle,
  and when the last one is back its twig says "all 6 back" for a while.
- A Vibe owlet that has waited over a minute and a half for the model's
  answer says how long ("Thinking · 3 min"), so a long answer doesn't look
  like a hang.
- Codex sessions are matched to their own log by the file each one has open,
  so several Codex runs in one folder, or in worktrees, no longer mix up
  their logs.
- Other agents run for a single prompt (`vibe -p …`, `codex exec …`) count as
  scripted, like the Agent SDK's sessions, and are hidden unless you show
  scripted sessions.
- **Plan limits say whose they are:** "Claude · 5 hours", "Codex Plus ·
  week", in the quick panel, the Roost and the widget, with the plan where
  the agent names it. They no longer read as if they applied to every owlet.

## 0.12.0

- **The Roost: your coding agents as owlets.** Claude Code (in a terminal,
  the Claude app's Code tab or the Agent SDK), Codex, Copilot CLI, OpenCode,
  Gemini CLI and a few others each get a pixel owlet that shows what it's
  doing: typing, searching, running a command, thinking, waiting for its
  helpers, stuck, napping, or waving when it needs you. Each agent has its
  own colour, and a session's helpers sit beside it.
- **In the menu bar and the quick panel.** While agents work, a small owlet
  sits beside the owl, with a dot when one needs you. The quick panel shows
  every owlet on a branch in a little night scene, a card for the one that
  needs you with what it asks and an Answer button, one line for the rest,
  and your plan limits as moons.
- **The Roost window.** **Now** shows what needs you as cards holding the
  actual question or command, with a countdown on a question; who's working,
  with their teams of helpers; what's done today; and who's napping. Beside
  it, today hour by hour, your plan limits, time by repository and a flight
  log. **Tree** puts every owlet on one pixel tree, a branch per repository,
  with nappers curled up in the hollow and finished ones asleep in the nest,
  under a sky that follows the time of day and the real moon (or one you
  pick in Settings → Agents). Pop the tree out into its own window and keep
  it on top. Open the Roost from the quick panel, by searching for "roost",
  or with `barnowl://roost`.
- **Show and Answer take you there:** to the very Terminal or iTerm tab the
  session runs in (macOS asks once whether Barn Owl may control it), or the
  very chat in the Claude app. Right-click an owlet to open its project in
  your editor, Terminal or Finder, or to hide or mute it.
- **The island at the notch.** When an agent needs you, gets stuck or
  finishes, a small island grows out of the notch (or hangs from the top of
  the screen). Hover to read the whole question or command. Choose Off, When
  One Needs You (the default) or While Agents Work in Settings → Agents. It
  stays away while you present or use an app full screen, doesn't ask about
  a session whose app is already in front, and leaves muted repositories
  alone.
- **Answer Claude Code from the island,** off by default: Allow Once, Deny,
  Always Allow, or one of a question's options, without switching apps.
  Turning it on adds two hooks to `~/.claude/settings.json`, after showing
  you the exact change and saving a backup. Nothing is allowed without your
  click, Always Allow adds only the rule Claude Code itself suggests (shown
  with exactly what it covers), and the usual prompt takes over whenever
  Barn Owl isn't running, you're in that session's app, or ten minutes pass.
- **Notifications** when an agent needs you, gets stuck after three failed
  commands in a row, or finishes a task that took a few minutes, but only
  when the island can't show it or you've been away.
- **Plan limits:** Claude's and Codex's 5-hour and weekly windows, with a
  forecast and a note at 80% and when a window resets. Claude's come from
  the Claude app's own usage history, Codex's from its session logs. For
  Claude's reset times, turn on Settings → Agents → Reset times for Claude:
  Claude Code's status line passes them on, and still looks as it did. An
  old reading says "as of". Barn Owl never asks a server and never reads a
  login.
- **Keep awake while an agent is working,** a new rule added the first time
  Barn Owl sees an agent: your Mac and its screen stay awake while one works
  and for five minutes after. A session waiting for you keeps it awake for
  five minutes only. With closed-lid mode on, a closed MacBook keeps running
  too.
- **A desktop widget,** small or medium: the Roost under a glass dome, its
  sky following the time of day. If Barn Owl hasn't updated it for 20
  minutes, it says "As of" with the time.
- **Your week in the Roost.** From Friday afternoon to Sunday, after a week
  with at least an hour of agent work, the quick panel offers a recap card
  to copy, save or share. Repository names stay hidden unless you show them.
- The setup guide has a new step for coding agents and the island.
- **What Barn Owl reads:** the agents' own session files in `~/.claude` and
  `~/.codex`, and the Claude app's session records and usage history. It
  shows each session's title, state, folder and branch and, while one waits
  for you, the command, file or question. It never keeps your prompts or
  replies, never reads logins, and nothing leaves your Mac. macOS may ask
  once whether Barn Owl can see your Desktop or Documents folder, when an
  agent works in a project there.
- **Turn features off in Settings → General → Features:** coding agents,
  clipboard history, the Nest, automatic presenter mode and disk space
  warnings. A feature that's off now doesn't run at all; before, the
  clipboard, the Nest and presenter mode still checked in the background.
  With coding agents off, Settings → Agents offers to remove Barn Owl's
  entries from Claude Code's settings.
- When more than one rule holds and one of them keeps the screen on, the
  screen now stays on; before, the first rule in the list decided. The
  quick panel says "Screen on" or "Screen can sleep", and which rule.
- A rule saved by a newer version of Barn Owl no longer makes an older one
  lose all your rules; it skips just that one.
- On a small screen, the middle of the quick panel scrolls, so its footer
  stays in reach.
- Barn Owl no longer looks over the whole menu bar every time a helper
  process starts or quits (browsers and test runs start many): only when an
  app that can have a menu bar icon does, and once per burst. Less CPU while
  you work.
- The owl on the Perch no longer gets cut off by the menu bar.

## 0.11.3

- **Closed-lid mode now works like Amphetamine's:** on battery, without an
  external display, and with no password or set-up, also on company-managed
  Macs. Barn Owl asks macOS's power manager directly not to sleep when the
  lid closes, only while keep awake is on. Locking the screen as the lid
  closes is now an option, off by default, as in Amphetamine. The old way (`pmset disablesleep`
  and a sudoers rule) is gone; if it left sleep disabled, Barn Owl turns it
  off, silently where it can. A leftover rule file is harmless; remove it
  with `sudo rm /private/etc/sudoers.d/barnowl` if you like.

## 0.11.2

- **Closed-lid mode on company-managed Macs.** Some Macs' administrator
  settings ask for a password for every change of this kind, which overrides
  the rule Barn Owl adds, so it couldn't switch closed-lid mode off and the Mac
  stopped sleeping with the lid closed. Barn Owl now checks that switching
  really works without a password before turning it on, explains when it
  can't, stops retrying, and if sleep is ever left disabled, says so and offers
  to fix it.

## 0.11.1

- **Fixes crashes at launch.** Moving the pointer over the owl made macOS
  throw an error each time (Barn Owl answered to the wrong names), which
  could leave it in a broken state and crash a moment later.
- **Setup no longer takes over the pointer.** Finishing setup, and Refresh
  Pictures in Settings, used to drag every hidden icon into view and back to
  photograph it; now they show all icons for a moment instead, and nothing
  moves.
- Barn Owl never borrows the pointer while you use it: an icon it brought out
  for you goes back once you pause, and moves it makes by itself wait without
  holding up the ones you ask for.
- Closed-lid mode can no longer end up on after keep awake quickly starts and
  stops.
- The "can't hide icons yet" alert only appears when you click the arrow, not
  out of nowhere.
- Big copies (whole log files, 6K screenshots) no longer slow Barn Owl down:
  text over a megabyte isn't kept, images are scaled down, and history is saved
  in the background.
- Dark Mode and presenter checks no longer freeze Barn Owl while macOS asks
  for permission or Control Center is busy.
- Clicking the covered desktop no longer takes the keyboard from your app.
- A clean-up that times out can't hang; "awake 0.2" means a minute, not
  forever; and a few rarer cases that could crash or loop are guarded.

## 0.11.0

- Without Screen Recording, icons whose name shows their state ("Wi‑Fi,
  connected", "OneDrive · Syncing") no longer count as new icons each time it
  changes, so they stay where you put them.
- Presenter mode no longer starts for apps that capture the screen all the
  time (DisplayLink, screen recorders), and the battery cutoff now lets the
  Mac sleep while presenting too.
- Closing Search or the clipboard hands the keyboard back to the app you
  were in.
- Updates found in the background say so in a notification instead of
  jumping in front of what you're typing, and a running keep-awake session
  carries on after the update.
- A very long number in search ("awake 99999999999999999999") no longer
  crashes Barn Owl; sessions are capped at a year.
- Turning clipboard history off clears it right away, on disk too.
- **Closed-lid mode now follows keep awake,** like Amphetamine with Power
  Protect. Close the lid while keep awake is on and your Mac keeps running,
  with the screen locked (unless an external display is connected);
  otherwise it sleeps as usual. Before, it stayed on until you turned it off.
  Turning it on asks for your password once, to add a rule that lets your
  account run exactly `pmset -a disablesleep 1` and `pmset -a disablesleep 0`
  without a password; turning it off removes the rule. On a MacBook, the
  setup guide offers it as one of its choices. If you had it on, Barn Owl
  offers to set this up, or to turn it off.
- Barn Owl no longer borrows your pointer while you're working. Icons it puts
  back in place, or shows because they changed, now wait until you pause, and
  an icon macOS won't let it keep in place (like Control Center's Display)
  is left alone instead of being dragged back every couple of minutes.

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
