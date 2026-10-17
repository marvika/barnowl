#!/bin/zsh
# Renders the app icon set from the owl drawn in the app (Brand/MenuBarOwl.swift).
set -euo pipefail
cd "${0:A:h}/.."
xcodegen generate --quiet
xcodebuild -project BarnOwl.xcodeproj -scheme BarnOwl -configuration Debug -derivedDataPath build/DerivedData build -quiet
"build/DerivedData/Build/Products/Debug/Barn Owl.app/Contents/MacOS/Barn Owl" \
  --render-icons BarnOwl/Resources/Assets.xcassets/AppIcon.appiconset
