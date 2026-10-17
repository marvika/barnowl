# Security

Barn Owl has Accessibility and Screen Recording access and reads your
clipboard, so security reports matter.

## Supported versions

Only the [latest release](https://github.com/marvika/barnowl/releases/latest)
gets fixes.

## Reporting a vulnerability

Please don't open a public issue. Report it privately through
**Security → Report a vulnerability** on this repository, or contact the
maintainer, [@marvika](https://github.com/marvika). You'll get a reply within
a week.

## What Barn Owl does with your data

- It works entirely on your Mac: no accounts or analytics. The only network
  request is the daily update check (Settings → General), which downloads
  `appcast.xml` from this repository and sends nothing about you.
- Updates are signed twice: with the maintainer's Developer ID and with an
  EdDSA key that never leaves the maintainer's Mac. Sparkle installs an update
  only when both match.
- Clipboard history skips copies marked private and known password managers,
  and never saves images to disk.
- Settings live in `~/Library/Preferences/io.github.marvika.BarnOwl.plist`;
  icon pictures and clipboard history in `~/Library/Application Support/Barn Owl`.
