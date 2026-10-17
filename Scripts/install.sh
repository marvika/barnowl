#!/bin/zsh
# Builds Barkeep in Release mode, installs it in /Applications and puts the
# `barkeep` command on your PATH. Run from anywhere: Scripts/install.sh
set -euo pipefail
cd "${0:A:h}/.."

echo "› Generating the Xcode project"
xcodegen generate --quiet

echo "› Building Barkeep (Release)"
xcodebuild -project Barkeep.xcodeproj -scheme Barkeep -configuration Release \
  -derivedDataPath build/Release build -quiet

app="build/Release/Build/Products/Release/Barkeep.app"
echo "› Installing in /Applications"
pkill -x Barkeep 2>/dev/null && sleep 1 || true
rm -rf /Applications/Barkeep.app
cp -R "$app" /Applications/

# Homebrew's bin folder is on PATH and writable without sudo; otherwise ~/.local/bin.
bin=/opt/homebrew/bin
[[ -w $bin ]] || { bin="$HOME/.local/bin"; mkdir -p "$bin"; }
cp Scripts/barkeep "$bin/barkeep"
echo "› Installed the barkeep command in $bin"

open /Applications/Barkeep.app
echo "✓ Barkeep is installed and running."
