# Contributing to Barn Owl

Thanks for helping! Bug reports, ideas and pull requests are all welcome.

## Reporting a bug

[Open an issue](https://github.com/marvika/barnowl/issues/new/choose) and
include your macOS version, your Mac (notched or not, external displays), and
the steps to see the problem. A screenshot of the menu bar helps, but check
it doesn't show anything private.

For security problems, see [SECURITY.md](SECURITY.md) instead.

## Building

You need macOS 26, Xcode 26 or later, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
open BarnOwl.xcodeproj
```

Run the tests with:

```bash
xcodebuild -project BarnOwl.xcodeproj -scheme BarnOwl test
```

Builds are ad-hoc signed, and macOS forgets an ad-hoc build's Accessibility
permission on every rebuild. To keep it, copy `Config/Local.xcconfig.example`
to `Config/Local.xcconfig` and set your team ID. That file is git-ignored.

`Scripts/install.sh` builds a Release copy into /Applications.
[docs/how-it-works.md](docs/how-it-works.md) explains how hiding, moving and
opening icons work.

## Making a release

Releases are signed with the maintainer's Developer ID and notarized, and
Sparkle updates installed copies from `appcast.xml` on main.

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`
   (Sparkle compares the build number), and rename **Unreleased** in
   `CHANGELOG.md` to the version. That section is what the update window shows.
2. Run `Scripts/release.sh --publish`. It builds, notarizes, staples, signs the
   zip for Sparkle, adds it to `appcast.xml`, points `Casks/barn-owl.rb` at it
   and creates a draft GitHub release. `Scripts/release.sh --dry-run` stops
   before notarizing and changes nothing.
3. Publish the draft, then commit `appcast.xml` and the cask and push them to
   main. Not before: the appcast would point at a download that isn't public.
4. Run `Scripts/update-tap.sh` to copy the cask to
   [marvika/homebrew-tap](https://github.com/marvika/homebrew-tap).

The Sparkle signing key lives only in the maintainer's login keychain (Sparkle's
`generate_keys` made it; the public half is `SUPublicEDKey` in Info.plist).
Keep a backup: without it, installed copies can't be updated. Export it with
`generate_keys -x <file>` from
`build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/`, store the
file somewhere safe, and delete it.

### On GitHub Actions

Pushing a `vX.Y.Z` tag runs `.github/workflows/release.yml`, which does step 2
for you and pushes the new appcast and cask to a `release/vX.Y.Z` branch. You
still publish the draft, merge that branch and run `Scripts/update-tap.sh`.
It needs these repository secrets (Settings → Secrets and variables → Actions):

| Secret | What to put in it |
|---|---|
| `DEVELOPER_ID_P12` | The Developer ID Application certificate and its private key, exported from Keychain Access as a .p12, then `base64 -i cert.p12 \| pbcopy` |
| `DEVELOPER_ID_P12_PASSWORD` | The password you gave the .p12 |
| `NOTARY_KEY_P8` | The contents of an App Store Connect API key (.p8) with the Developer role (App Store Connect → Users and Access → Integrations) |
| `NOTARY_KEY_ID` | That key's ID |
| `NOTARY_ISSUER` | The issuer ID shown above the keys |
| `SPARKLE_PRIVATE_KEY` | The contents of the file `generate_keys -x` writes |

The team ID (2S5J2CYWPZ) is set in the workflow. Until the secrets exist, a tag
push fails at signing and nothing is published.

## Pull requests

- Keep each pull request to one change, and describe what it fixes or adds
  and how you tested it.
- The Xcode project is generated: change `project.yml`, not
  `BarnOwl.xcodeproj`.
- Add tests for logic that doesn't need a real menu bar (see `BarnOwlTests`).
- Match the code around you: Swift 6, SwiftUI with AppKit where needed, and
  short comments that say why.
- Interface text is plain and short, in sentence case for descriptions and
  title case for buttons and menu items.
- Screenshots come from demo mode (`Scripts/demo.sh`), never from your own
  menu bar or clipboard.
- With Reduce Motion on, new animations should stay still.

By contributing, you agree that your contribution is licensed under the
[MIT License](LICENSE).

## Code of conduct

This project follows the [Code of Conduct](CODE_OF_CONDUCT.md).
