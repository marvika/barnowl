#!/bin/zsh
# Records the README's agents GIF from the demo copy (Scripts/demo.sh), driven
# by barnowl:// links over the dusk stage: an agent asks at the notch, the
# island opens to the question, the quick panel shows the owlets, then the
# Roost's Now view and its tree. Keep hands off the Mac (about 20 seconds).
#
#   Scripts/record-roost.sh          writes docs/images/roost.gif
set -euo pipefail
cd "${0:A:h}/.."

app="$PWD/build/Demo/Barn Owl.app"
go() { open -g -a "$app" "barnowl://$1"; }
# Windows only come above the stage with the demo in front.
front() { osascript -e 'tell application id "io.github.marvika.BarnOwl.demo" to activate' 2>/dev/null || true; }
[[ -d $app ]] || Scripts/demo.sh
pgrep -f "build/Demo/Barn Owl.app" >/dev/null || { open "$app"; sleep 4; }

# From just left of the notch to the right edge: the island, the owl's
# panel and the Roost window, which demo.sh places inside this region.
screen_width=$(osascript -e 'tell application "Finder" to get item 3 of (get bounds of window of desktop)')
width=$((screen_width / 2 + 300)); height=820
region="$((screen_width - width)),0,$width,$height"

mkdir -p build/demo
go "roost?close=1"
go "nest?clear=1"
go "island?open=0"
go stage
sleep 1.5
rm -f build/demo/roost.mov
screencapture -v -V 21 -R "$region" -x build/demo/roost.mov &
recorder=$!
sleep 1.5;  go "island?open=1"        # the question, its options, Allow-free answers
sleep 3.5;  go "island?open=0"        # back to a quiet pill
sleep 0.8;  go quick                  # the owlets on their branch, the one that's asking
sleep 3.4;  go quick
sleep 0.6;  front; go "roost?view=now"   # the Roost: what needs you first
sleep 3.6;  go "roost?view=tree"      # and every owlet on the tree
sleep 4.0;  go "roost?close=1"        # closed, so the loop joins up
wait $recorder
go stage

swift Scripts/make-gif.swift build/demo/roost.mov docs/images/roost.gif 12 760 0
