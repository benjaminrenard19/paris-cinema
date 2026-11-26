#!/bin/bash
# Sloth Cinema: pull the latest code and, when the app changed (or every 5 days, so the free
# 7-day signing never runs out), build it and install it on the iPhone. Run by launchd every
# hour once scripts/mac/install-autoinstall.sh has been run. Needs the Mac awake and unlocked,
# Xcode signed in to your Apple ID, and the iPhone on a cable or on the same Wi-Fi with
# "Connect via network" ticked in Xcode › Window › Devices and Simulators.
#
#   bash scripts/mac/autoinstall.sh            # what launchd runs
#   bash scripts/mac/autoinstall.sh --force    # build and install now
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PHONE="${SLOTH_PHONE:-iPhone de Ben}"
BUILD="$HOME/Library/Developer/SlothCinemaBuild"
STAMP="$BUILD/installed-commit"
RENEW_DAYS=5
mkdir -p "$BUILD"

say() { echo "$(date '+%Y-%m-%d %H:%M') $*"; }
notify() { /usr/bin/osascript -e "display notification \"$1\" with title \"Sloth Cinema\"" >/dev/null 2>&1 || true; }

cd "$REPO" || exit 1
git pull --rebase --autostash --quiet || say "git pull failed, building what is here"
HEAD_NOW="$(git rev-parse HEAD)"
LAST="$(cat "$STAMP" 2>/dev/null || echo none)"

if [ "${1:-}" != "--force" ] && [ "$LAST" != none ]; then
  AGE_DAYS=$(( ( $(date +%s) - $(stat -f %m "$STAMP") ) / 86400 ))
  if [ "$AGE_DAYS" -lt "$RENEW_DAYS" ]; then
    if [ "$LAST" = "$HEAD_NOW" ] || git diff --quiet "$LAST" "$HEAD_NOW" -- ParisCinema ParisCinema.xcodeproj ParisCinema-Info.plist 2>/dev/null; then
      exit 0   # nothing new for the app
    fi
  fi
fi

# The iPhone's id, from the list of connected devices.
# Only the "== Devices ==" section: an offline iPhone is listed under "== Devices Offline ==".
UDID="$(xcrun xctrace list devices 2>/dev/null | awk '/^== Devices ==/{f=1;next} /^==/{f=0} f' \
  | grep -F "$PHONE" | head -1 | sed -E 's/.*\(([0-9A-Fa-f-]{20,})\)[[:space:]]*$/\1/')"
if [ -z "$UDID" ]; then
  say "$PHONE is not reachable (cable or Wi-Fi). Trying again next hour."
  exit 0
fi

say "building for $PHONE ($UDID) at ${HEAD_NOW:0:7}"
if ! xcodebuild -project ParisCinema.xcodeproj -scheme ParisCinema -configuration Debug \
      -destination "id=$UDID" -derivedDataPath "$BUILD/DerivedData" \
      -allowProvisioningUpdates -quiet build; then
  say "build failed"
  notify "The build failed. Open Xcode to see why."
  exit 1
fi

APP="$BUILD/DerivedData/Build/Products/Debug-iphoneos/ParisCinema.app"
if xcrun devicectl device install app --device "$UDID" "$APP" >/dev/null; then
  echo "$HEAD_NOW" > "$STAMP"
  say "installed ${HEAD_NOW:0:7} on $PHONE"
  notify "New version installed on $PHONE."
else
  say "install failed (is the iPhone unlocked?). Trying again next hour."
fi
