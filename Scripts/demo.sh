#!/bin/zsh
# Runs Barn Owl in demo mode for screenshots: a separate copy with its own
# settings and a made-up menu bar, so nothing real is shown or changed.
#
#   Scripts/demo.sh           start the demo (quits your Barn Owl)
#   Scripts/demo.sh setup     start it with the setup guide showing
#   Scripts/demo.sh stop      quit the demo and start your Barn Owl again
set -euo pipefail
cd "${0:A:h}/.."

domain=io.github.marvika.BarnOwl.demo
demo="build/Demo/Barn Owl.app"

if [[ "${1:-}" == stop ]]; then
  pkill -f "build/Demo/Barn Owl.app" 2>/dev/null || true
  open "/Applications/Barn Owl.app" 2>/dev/null || true
  exit 0
fi

echo "› Building"
xcodegen generate --quiet
xcodebuild -project BarnOwl.xcodeproj -scheme BarnOwl -configuration Release \
  -derivedDataPath build/Release build -quiet

echo "› Making the demo copy"
rm -rf build/Demo && mkdir -p build/Demo
cp -R "build/Release/Build/Products/Release/Barn Owl.app" "$demo"
plutil -replace CFBundleIdentifier -string "$domain" "$demo/Contents/Info.plist"
codesign --force --deep --sign - "$demo" 2>/dev/null

echo "› Preparing demo settings and files"
mkdir -p "/tmp/Barn Owl Demo"
for f in "Project Brief.pdf" "Roadmap.key" "Screenshot.png"; do : > "/tmp/Barn Owl Demo/$f"; done
defaults delete "$domain" 2>/dev/null || true
screen=$(osascript -e 'tell application "Finder" to get bounds of window of desktop' | tr -d ' ')
python3 - "$domain" "${1:-}" "$screen" <<'PY'
import json, plistlib, subprocess, sys, uuid
domain, mode = sys.argv[1], sys.argv[2]
_, _, screen_width, screen_height = (int(v) for v in sys.argv[3].split(","))
group = str(uuid.UUID("0D3E0000-0000-4000-8000-00000000C0DE"))
settings = {
    "BarnOwlDemo": True,
    "hasShownWelcome": mode != "setup",
    "alwaysHiddenEnabled": True,
    "appliedDefaultLayout": True,
    "placedKeepAwakeIcon": True,
    "hiddenIconsDisplay": "perch",
    "keepAwakeRules": json.dumps([
        {"id": "0D3E0000-0000-4000-8000-0000000001A1", "conditions": [{"onPower": {}}, {"externalDisplay": {}}],
         "isEnabled": True, "allowDisplaySleep": False},
        {"id": "0D3E0000-0000-4000-8000-0000000001A2", "conditions": [{"microphoneInUse": {}}],
         "isEnabled": True, "allowDisplaySleep": False},
        {"id": "0D3E0000-0000-4000-8000-0000000001A3",
         "conditions": [{"schedule": {"weekdays": [2, 3, 4, 5, 6], "startMinute": 480, "endMinute": 1020}}],
         "isEnabled": False, "allowDisplaySleep": True},
    ]).encode(),
    "groups": json.dumps([{"id": group, "name": "Work", "symbol": "briefcase.fill",
                           "memberKeys": ["demo/VPN", "demo/Mail", "demo/Chat"]}]).encode(),
    # Barn Owl's own icons right of the divider (smaller is further right).
    "NSStatusItem Preferred Position BarnOwlToggle": 0.0,
    "NSStatusItem Preferred Position BarnOwlKeepAwake": 0.3,
    "NSStatusItem Preferred Position BarnOwlGroup-" + group: 0.6,
    "NSStatusItem Preferred Position BarnOwlSeparator": 1.0,
    "NSStatusItem Preferred Position BarnOwlAlwaysHidden": 10000.0,
    # The Roost opens right of the notch, inside what record-roost.sh films.
    "NSWindow Frame BarnOwlRoost": f"{screen_width - 1120} {screen_height - 100 - 700} 1100 700 0 0 {screen_width} {screen_height}",
}
subprocess.run(["defaults", "import", domain, "-"], input=plistlib.dumps(settings), check=True)
PY

echo "› Starting the demo"
pkill -x "Barn Owl" 2>/dev/null && sleep 1 || true
open "$demo"
echo "✓ Demo running. Scripts/demo.sh stop brings your Barn Owl back."
