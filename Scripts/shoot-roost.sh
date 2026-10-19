#!/bin/zsh
# Takes the README's agents screenshots from the demo copy (Scripts/demo.sh),
# with its made-up owlets, driven by barnowl:// links. Keep hands off the Mac
# while it runs (about 40 seconds).
#
#   Scripts/shoot-roost.sh          writes docs/images/{roost-now,roost-tree,island,quick-panel-agents,setup-agents}.png
set -euo pipefail
cd "${0:A:h}/.."

app="$PWD/build/Demo/Barn Owl.app"
out=docs/images
go() { open -g -a "$app" "barnowl://$1"; }
window() { swift Scripts/window-of.swift "$1"; }
[[ -d $app ]] || Scripts/demo.sh
pgrep -f "build/Demo/Barn Owl.app" >/dev/null || { open "$app"; sleep 4; }

# In front, so the window looks active (coloured buttons and switches).
front() { osascript -e 'tell application id "io.github.marvika.BarnOwl.demo" to activate' 2>/dev/null || true; sleep 0.6; }

# A whole window, with its shadow.
shoot_window() {
  front
  local found; found=$(window "$1")
  [[ -n $found ]] || { echo "✗ No $1 window for $2"; return 1; }
  screencapture -x -l "${found%% *}" "$out/$2"
  echo "✓ $out/$2"
}

# A region around a window, with what's behind it (the island under the notch).
shoot_around() {
  local found; found=$(window "$1")
  [[ -n $found ]] || { echo "✗ No $1 window for $2"; return 1; }
  local parts=(${=found}) margin=$3
  screencapture -x -R "$((parts[2] - margin)),0,$((parts[4] + margin * 2)),$((parts[5] + parts[3] + 8))" "$out/$2"
  echo "✓ $out/$2"
}

go stage; go "nest?clear=1"; sleep 1.5

go "roost?view=now"; sleep 2.5
shoot_window largest roost-now.png
go "roost?view=tree"; sleep 2.5
shoot_window largest roost-tree.png
go "roost?close=1"; sleep 1

go "island?open=1"; sleep 1.5
shoot_around island island.png 40
go "island?open=0"; sleep 0.8

go quick; sleep 1.5
shoot_window panel quick-panel-agents.png
go quick; sleep 0.8

go "setup?step=agents"; sleep 2.5
shoot_window largest setup-agents.png

go stage
echo "Close the setup guide by hand; Scripts/demo.sh stop brings your Barn Owl back."
