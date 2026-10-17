#!/bin/zsh
# Builds a release of Barn Owl that opens without warnings on any Mac: signed
# with a Developer ID, notarized by Apple and stapled. Writes
# build/dist/BarnOwl-<version>.zip and the barnowl command next to it, adds the
# release to the update feed (appcast.xml) and points the Homebrew cask
# (Casks/barn-owl.rb) at the new zip.
#
#   Scripts/release.sh             build, notarize and check
#   Scripts/release.sh --publish   also create the GitHub release (draft)
#   Scripts/release.sh --dry-run   build, sign and check only: no notarizing,
#                                  and appcast.xml and the cask stay as they are
#
# Before a release, bump MARKETING_VERSION and CURRENT_PROJECT_VERSION in
# project.yml and rename "Unreleased" in CHANGELOG.md to the version: its
# notes are what the update window shows.
#
# Needs, once:
#   - a "Developer ID Application" certificate in your keychain
#   - DEVELOPMENT_TEAM in Config/Local.xcconfig, or BARNOWL_TEAM set
#   - notarytool credentials saved in the keychain:
#       xcrun notarytool store-credentials "barkeep-notary" \
#         --apple-id you@example.com --team-id YOURTEAMID
#     (or another profile name, passed in NOTARY_PROFILE)
#   - the Sparkle signing key in your login keychain, made once with Sparkle's
#     generate_keys (see CONTRIBUTING.md). Keep a backup of it.
set -euo pipefail
cd "${0:A:h}/.."

mode=${1:-}
[[ -z $mode || $mode == --publish || $mode == --dry-run ]] || { echo "✗ Unknown option $mode"; exit 1; }

team=${BARNOWL_TEAM:-$(sed -n 's/^DEVELOPMENT_TEAM *= *//p' Config/Local.xcconfig 2>/dev/null | head -1)}
profile=${NOTARY_PROFILE:-barkeep-notary}
version=$(sed -n 's/^ *MARKETING_VERSION: *//p' project.yml | head -1)
build=$(sed -n 's/^ *CURRENT_PROJECT_VERSION: *//p' project.yml | head -1)
minimum_macos=$(sed -n 's/^ *macOS: *"\{0,1\}\([0-9.]*\)"\{0,1\}/\1/p' project.yml | head -1)
[[ -n $team ]] || { echo "✗ Set DEVELOPMENT_TEAM in Config/Local.xcconfig or BARNOWL_TEAM"; exit 1; }
[[ -n $version && -n $build ]] || { echo "✗ No MARKETING_VERSION or CURRENT_PROJECT_VERSION in project.yml"; exit 1; }

# Sparkle offers an update when its build number is higher than the installed one.
if grep -q "<sparkle:version>$build</sparkle:version>" appcast.xml; then
  echo "✗ appcast.xml already has build $build. Bump CURRENT_PROJECT_VERSION in project.yml."
  [[ $mode == --dry-run ]] || exit 1
fi

# The update window shows this version's section of the changelog.
notes=$(awk -v v="$version" '$0 == "## " v {on=1; next} /^## / {on=0} on' CHANGELOG.md | sed -e '/./,$!d')
if [[ -z $notes ]]; then
  [[ $mode == --dry-run ]] || { echo "✗ CHANGELOG.md has no \"## $version\" section"; exit 1; }
  notes=$(awk '$0 == "## Unreleased" {on=1; next} /^## / {on=0} on' CHANGELOG.md | sed -e '/./,$!d')
fi

dist=build/dist
app="build/Distribution/Build/Products/Release/Barn Owl.app"
zip="$dist/BarnOwl-$version.zip"
sparkle_bin=build/Distribution/SourcePackages/artifacts/sparkle/Sparkle/bin

echo "› Building Barn Owl $version ($build) for distribution (team $team)"
xcodegen generate --quiet
rm -rf build/Distribution
xcodebuild -project BarnOwl.xcodeproj -scheme BarnOwl -configuration Release \
  -derivedDataPath build/Distribution build -quiet \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" DEVELOPMENT_TEAM="$team" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO

# Xcode signs Sparkle.framework when it copies it, but not the helpers inside
# it, and notarization wants every one signed with the Developer ID. Sign them
# inside out, then the app again with its own entitlements.
echo "› Signing Sparkle's helpers"
identity=$(security find-identity -v -p codesigning | grep "Developer ID Application: .*($team)" | head -1 | awk '{print $2}')
[[ -n $identity ]] || { echo "✗ No Developer ID Application certificate for team $team"; exit 1; }
sparkle="$app/Contents/Frameworks/Sparkle.framework"
sign=(codesign --force --timestamp --options runtime --sign "$identity")
$sign "$sparkle/Versions/B/XPCServices/Installer.xpc"
$sign --preserve-metadata=entitlements "$sparkle/Versions/B/XPCServices/Downloader.xpc"
$sign "$sparkle/Versions/B/Autoupdate"
$sign "$sparkle/Versions/B/Updater.app"
$sign "$sparkle"
$sign --preserve-metadata=entitlements "$app"

echo "› Checking the signature"
codesign --verify --deep --strict "$app"
codesign -dvv "$app" 2>&1 | grep -E "^(Authority=Developer ID Application|Timestamp=|Runtime Version=)" \
  || { echo "✗ Not signed with a Developer ID, a timestamp and the hardened runtime"; exit 1; }
if codesign -d --entitlements - "$app" 2>/dev/null | grep -q get-task-allow; then
  echo "✗ The app has the get-task-allow entitlement, which notarization rejects"; exit 1
fi
for helper in "$sparkle" "$sparkle"/Versions/B/{Autoupdate,Updater.app,XPCServices/*.xpc}; do
  [[ $(codesign -dvv "$helper" 2>&1) == *$'\n'"Authority=Developer ID Application"* ]] \
    || { echo "✗ ${helper#$app/} isn't signed with the Developer ID"; exit 1; }
done

rm -rf "$dist" && mkdir -p "$dist"
if [[ $mode == --dry-run ]]; then
  echo "› Dry run: not notarizing"
else
  echo "› Sending it to Apple to notarize (usually a few minutes)"
  ditto -c -k --keepParent "$app" "$dist/upload.zip"
  xcrun notarytool submit "$dist/upload.zip" --keychain-profile "$profile" --wait
  rm "$dist/upload.zip"

  echo "› Stapling the ticket, so it opens offline too"
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  spctl --assess --type execute --verbose=2 "$app"
fi

ditto -c -k --keepParent "$app" "$zip"
cp Scripts/barnowl "$dist/barnowl"
shasum -a 256 "$zip" "$dist/barnowl" | tee "$dist/SHA256SUMS"
echo "✓ $zip is ready"

echo "› Signing the zip for Sparkle"
enclosure=$("$sparkle_bin/sign_update" "$zip") || true
if [[ $enclosure != *edSignature=* ]]; then
  echo "✗ sign_update found no Sparkle key in your keychain. Import your backup with"
  echo "  $sparkle_bin/generate_keys -f <file>"
  exit 1
fi
cat <<EOF
! Back up the Sparkle signing key if you haven't: without it, installed copies
  can never be updated again. Export it, keep it in your password manager and
  delete the file:
    $sparkle_bin/generate_keys -x sparkle-key.txt
EOF
release_url="https://github.com/marvika/barnowl/releases/tag/v$version"
cat > "$dist/appcast-item.xml" <<EOF
        <item>
            <title>Barn Owl $version</title>
            <link>$release_url</link>
            <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
            <sparkle:version>$build</sparkle:version>
            <sparkle:shortVersionString>$version</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>$minimum_macos</sparkle:minimumSystemVersion>
            <sparkle:fullReleaseNotesLink>$release_url</sparkle:fullReleaseNotesLink>
            <description sparkle:format="markdown"><![CDATA[
$notes
]]></description>
            <enclosure url="https://github.com/marvika/barnowl/releases/download/v$version/BarnOwl-$version.zip" $enclosure type="application/octet-stream"/>
        </item>
EOF

if [[ $mode == --dry-run ]]; then
  echo "✓ Dry run done. The appcast item is in $dist/appcast-item.xml; appcast.xml and the cask are unchanged."
  exit 0
fi

echo "› Adding $version to appcast.xml"
awk -v item="$dist/appcast-item.xml" '
  { print }
  /<!-- Releases, newest first -->/ { while ((getline line < item) > 0) print line }
' appcast.xml > "$dist/appcast.xml"
xmllint --noout "$dist/appcast.xml"
mv "$dist/appcast.xml" appcast.xml

echo "› Updating the Homebrew cask"
sha=$(shasum -a 256 "$zip" | cut -d' ' -f1)
sed -i '' -e "s/^  version \".*\"/  version \"$version\"/" -e "s/^  sha256 \".*\"/  sha256 \"$sha\"/" Casks/barn-owl.rb
echo "✓ Casks/barn-owl.rb now installs $version"

if [[ $mode == --publish ]]; then
  echo "› Creating a draft GitHub release v$version"
  gh release create "v$version" "$zip" "$dist/barnowl" "$dist/SHA256SUMS" \
    --draft --title "Barn Owl $version" --notes "$notes"
  echo "✓ Draft created."
fi

cat <<EOF

Next, in this order:
  1. Publish the draft release v$version on GitHub (create it with --publish).
  2. Commit appcast.xml and Casks/barn-owl.rb and push them to main. Installed
     copies offer the update once appcast.xml is on main, so do this only after
     the release is public: before that, its download link doesn't work.
  3. Run Scripts/update-tap.sh to copy the cask to marvika/homebrew-tap.
EOF
