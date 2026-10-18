#!/bin/zsh
# Renders the app icon's layers (sky, moon, owl) from the owl drawn in the app
# (Brand/MenuBarOwl.swift) into BarnOwl/Resources/AppIcon.icon, the Liquid
# Glass icon format. Open AppIcon.icon in Icon Composer to fine-tune the glass.
set -euo pipefail
cd "${0:A:h}/.."
xcodegen generate --quiet
xcodebuild -project BarnOwl.xcodeproj -scheme BarnOwl -configuration Debug -derivedDataPath build/DerivedData build -quiet
"build/DerivedData/Build/Products/Debug/Barn Owl.app/Contents/MacOS/Barn Owl" \
  --render-icon-layers BarnOwl/Resources/AppIcon.icon/Assets
