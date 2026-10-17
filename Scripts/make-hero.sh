#!/bin/zsh
# Draws the README's owl pictures with the app's own drawing code, then
# composes docs/images/hero.png from them and the screenshots.
set -euo pipefail
cd "${0:A:h}/.."

xcodegen generate --quiet
xcodebuild -project BarnOwl.xcodeproj -scheme BarnOwl -configuration Debug \
  -derivedDataPath build/DerivedData build -quiet
app="build/DerivedData/Build/Products/Debug/Barn Owl.app/Contents/MacOS/Barn Owl"
"$app" --render-owl build/hero-owl.png
"$app" --render-owl-strip docs/images/owl-moods.png
swift Scripts/make-hero.swift
