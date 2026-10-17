#!/bin/zsh
# Builds a release of Barn Owl that opens without warnings on any Mac: signed
# with a Developer ID, notarized by Apple and stapled. Writes
# build/dist/BarnOwl-<version>.zip and the barnowl command next to it, and
# points the Homebrew cask (Casks/barn-owl.rb) at the new zip.
#
#   Scripts/release.sh             build, notarize and check
#   Scripts/release.sh --publish   also create the GitHub release (draft)
#
# Needs, once:
#   - a "Developer ID Application" certificate in your keychain
#   - DEVELOPMENT_TEAM in Config/Local.xcconfig, or BARNOWL_TEAM set
#   - notarytool credentials saved in the keychain:
#       xcrun notarytool store-credentials "barkeep-notary" \
#         --apple-id you@example.com --team-id YOURTEAMID
#     (or another profile name, passed in NOTARY_PROFILE)
set -euo pipefail
cd "${0:A:h}/.."

team=${BARNOWL_TEAM:-$(sed -n 's/^DEVELOPMENT_TEAM *= *//p' Config/Local.xcconfig 2>/dev/null | head -1)}
profile=${NOTARY_PROFILE:-barkeep-notary}
version=$(sed -n 's/^ *MARKETING_VERSION: *//p' project.yml | head -1)
[[ -n $team ]] || { echo "✗ Set DEVELOPMENT_TEAM in Config/Local.xcconfig or BARNOWL_TEAM"; exit 1; }
[[ -n $version ]] || { echo "✗ No MARKETING_VERSION in project.yml"; exit 1; }

dist=build/dist
app="build/Distribution/Build/Products/Release/Barn Owl.app"
zip="$dist/BarnOwl-$version.zip"

echo "› Building Barn Owl $version for distribution (team $team)"
xcodegen generate --quiet
rm -rf build/Distribution
xcodebuild -project BarnOwl.xcodeproj -scheme BarnOwl -configuration Release \
  -derivedDataPath build/Distribution build -quiet \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" DEVELOPMENT_TEAM="$team" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO

echo "› Checking the signature"
codesign --verify --deep --strict "$app"
codesign -dvv "$app" 2>&1 | grep -E "^(Authority=Developer ID Application|Timestamp=|Runtime Version=)" \
  || { echo "✗ Not signed with a Developer ID, a timestamp and the hardened runtime"; exit 1; }
if codesign -d --entitlements - "$app" 2>/dev/null | grep -q get-task-allow; then
  echo "✗ The app has the get-task-allow entitlement, which notarization rejects"; exit 1
fi

echo "› Sending it to Apple to notarize (usually a few minutes)"
rm -rf "$dist" && mkdir -p "$dist"
ditto -c -k --keepParent "$app" "$dist/upload.zip"
xcrun notarytool submit "$dist/upload.zip" --keychain-profile "$profile" --wait
rm "$dist/upload.zip"

echo "› Stapling the ticket, so it opens offline too"
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"

ditto -c -k --keepParent "$app" "$zip"
cp Scripts/barnowl "$dist/barnowl"
shasum -a 256 "$zip" "$dist/barnowl" | tee "$dist/SHA256SUMS"
echo "✓ $zip is ready"

echo "› Updating the Homebrew cask"
sha=$(shasum -a 256 "$zip" | cut -d' ' -f1)
sed -i '' -e "s/^  version \".*\"/  version \"$version\"/" -e "s/^  sha256 \".*\"/  sha256 \"$sha\"/" Casks/barn-owl.rb
echo "✓ Casks/barn-owl.rb now installs $version. Commit it with the release; copy it to"
echo "  your homebrew-tap repository too, if you have one."

if [[ "${1:-}" == --publish ]]; then
  echo "› Creating a draft GitHub release v$version"
  gh release create "v$version" "$zip" "$dist/barnowl" "$dist/SHA256SUMS" \
    --draft --title "Barn Owl $version" --generate-notes
  echo "✓ Draft created. Review it on GitHub, then publish."
fi
