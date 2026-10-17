#!/bin/zsh
# Copies Casks/barn-owl.rb to the Homebrew tap (github.com/marvika/homebrew-tap),
# so `brew install --cask marvika/tap/barn-owl` gets the new version. Run it
# after Scripts/release.sh, once the GitHub release is published.
#
#   Scripts/update-tap.sh            show the change and ask before pushing
#   Scripts/update-tap.sh --yes      push without asking
set -euo pipefail
cd "${0:A:h}/.."

tap_repo=marvika/homebrew-tap
version=$(sed -n 's/^  version "\(.*\)"/\1/p' Casks/barn-owl.rb)
[[ -n $version ]] || { echo "✗ No version in Casks/barn-owl.rb"; exit 1; }

# Brew users would get a broken download from a draft release.
if [[ $(gh release view "v$version" --repo marvika/barnowl --json isDraft --jq .isDraft 2>/dev/null) != false ]]; then
  echo "✗ Release v$version isn't published yet. Publish it on GitHub first."
  exit 1
fi

tap=build/homebrew-tap
rm -rf "$tap"
gh repo clone "$tap_repo" "$tap" -- --depth 1 --quiet
mkdir -p "$tap/Casks"
cp Casks/barn-owl.rb "$tap/Casks/barn-owl.rb"
if git -C "$tap" diff --quiet; then
  echo "✓ The tap already installs $version"
  exit 0
fi
git -C "$tap" --no-pager diff

if [[ ${1:-} != --yes ]]; then
  read -q "?Push this to $tap_repo? [y/N] " || { echo; echo "Not pushed. The change is in $tap."; exit 1; }
  echo
fi
git -C "$tap" commit --quiet -am "barn-owl $version"
git -C "$tap" push --quiet
echo "✓ $tap_repo now installs Barn Owl $version"
