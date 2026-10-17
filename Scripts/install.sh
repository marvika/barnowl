#!/bin/zsh
# Builds Barn Owl in Release mode, installs it in /Applications and puts the
# `barnowl` command on your PATH. Run from anywhere: Scripts/install.sh
set -euo pipefail
cd "${0:A:h}/.."

echo "› Generating the Xcode project"
xcodegen generate --quiet

echo "› Building Barn Owl (Release)"
xcodebuild -project BarnOwl.xcodeproj -scheme BarnOwl -configuration Release \
  -derivedDataPath build/Release build -quiet

app="build/Release/Build/Products/Release/Barn Owl.app"
echo "› Installing in /Applications"
pkill -x "Barn Owl" 2>/dev/null && sleep 1 || true
# Barn Owl used to be called Barkeep; the old copy would fight over the menu bar.
if [[ -d /Applications/Barkeep.app ]]; then
  pkill -x Barkeep 2>/dev/null || true
  mv /Applications/Barkeep.app ~/.Trash/ && echo "› Moved the old Barkeep.app to the Trash"
fi
rm -rf "/Applications/Barn Owl.app"
cp -R "$app" /Applications/

# Homebrew's bin folder is on PATH and writable without sudo; otherwise ~/.local/bin.
bin=/opt/homebrew/bin
[[ -w $bin ]] || { bin="$HOME/.local/bin"; mkdir -p "$bin"; }
cp Scripts/barnowl "$bin/barnowl"
echo "› Installed the barnowl command in $bin"

open "/Applications/Barn Owl.app"
echo "✓ Barn Owl is installed and running."
