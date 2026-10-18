#!/bin/zsh
# Records the README's demo GIF from the demo copy (Scripts/demo.sh), driven
# by barnowl:// links rather than the mouse, over a dusk stage that hides
# your desktop. Keep hands off the Mac while it runs (about 20 seconds).
#
#   Scripts/record-demo.sh          writes docs/images/demo.gif
set -euo pipefail
cd "${0:A:h}/.."

app="$PWD/build/Demo/Barn Owl.app"
go() { open -g -a "$app" "barnowl://$1"; }
[[ -d $app ]] || Scripts/demo.sh
pgrep -f "build/Demo/Barn Owl.app" >/dev/null || { open "$app"; sleep 4; }

# The right-hand part of the main screen: the owl, the arrow and the panels.
screen_width=$(osascript -e 'tell application "Finder" to get item 3 of (get bounds of window of desktop)')
width=760; height=540
region="$((screen_width - width)),0,$width,$height"

mkdir -p build/demo
go keep-awake/stop
go stage
sleep 1.5
rm -f build/demo/demo.mov
screencapture -v -V 13 -R "$region" -x build/demo/demo.mov &
recorder=$!
sleep 1.2;  go bar                       # the hidden icons settle onto the Perch
sleep 3.0;  go bar                       # tucked away again
sleep 0.8;  go quick                     # the quick panel, the owl asleep
sleep 1.6;  go "keep-awake?minutes=60"   # wide awake, counting down
sleep 3.6;  go quick                     # closed; the countdown stays in the menu bar
sleep 1.2;  go keep-awake/stop           # back to sleep, so the loop joins up
wait $recorder
go stage

swift Scripts/make-gif.swift build/demo/demo.mov docs/images/demo.gif 12 "$width" 160
