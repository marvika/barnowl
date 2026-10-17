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
