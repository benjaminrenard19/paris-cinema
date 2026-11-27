#!/bin/bash
# Sloth Cinema: pull the latest code and, when the app changed (or every 5 days, so the free
# 7-day signing never runs out), build it and install it on each iPhone in SLOTH_PHONES. Run by launchd every
# hour once scripts/mac/install-autoinstall.sh has been run. Needs the Mac awake and unlocked,
# Xcode signed in to your Apple ID, and the iPhone on a cable or on the same Wi-Fi with
# "Connect via network" ticked in Xcode › Window › Devices and Simulators.
#
#   bash scripts/mac/autoinstall.sh            # what launchd runs
#   bash scripts/mac/autoinstall.sh --force    # build and install now
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
# The iPhones to install on, by the name shown in Finder / Xcode, separated by commas.
PHONES="${SLOTH_PHONES:-iPhone de Ben,iPhone de Camille Devisme}"
BUILD="$HOME/Library/Developer/SlothCinemaBuild"
STAMP="$BUILD/installed-commit"
RENEW_DAYS=5
mkdir -p "$BUILD"

say() { echo "$(date '+%Y-%m-%d %H:%M') $*"; }
notify() { /usr/bin/osascript -e "display notification \"$1\" with title \"Sloth Cinema\"" >/dev/null 2>&1 || true; }

cd "$REPO" || exit 1
# A pull that was cut off leaves its stash in MERGE_AUTOSTASH, which blocks the next pull: keep it in the stash list.
if [ -f .git/MERGE_AUTOSTASH ] && [ ! -f .git/index.lock ]; then
  git stash store -m "autostash kept after an interrupted pull" "$(cat .git/MERGE_AUTOSTASH)" && rm -f .git/MERGE_AUTOSTASH
fi
git -c user.name="Sloth Cinema" -c user.email=sloth@localhost pull --rebase --autostash --quiet \
  || say "git pull failed, building what is here"
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

# Each iPhone in SLOTH_PHONES (comma-separated names), if it's connected (cable or Wi-Fi).
installed=0
IFS=',' read -ra NAMES <<< "$PHONES"
for PHONE in "${NAMES[@]}"; do
  PHONE="$(echo "$PHONE" | sed -E 's/^ +| +$//g')"
  # Only the "== Devices ==" section: an offline iPhone is listed under "== Devices Offline ==".
  UDID="$(xcrun xctrace list devices 2>/dev/null | awk '/^== Devices ==/{f=1;next} /^==/{f=0} f' \
    | grep -F "$PHONE" | head -1 | sed -E 's/.*\(([0-9A-Fa-f-]{20,})\)[[:space:]]*$/\1/')"
  if [ -z "$UDID" ]; then
    say "$PHONE is not reachable (cable or Wi-Fi). Trying again next hour."
    continue
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
    installed=$((installed + 1))
    say "installed ${HEAD_NOW:0:7} on $PHONE"
    notify "New version installed on $PHONE."
  else
    say "install on $PHONE failed (is it unlocked?). Trying again next hour."
  fi
done
[ "$installed" -gt 0 ] && echo "$HEAD_NOW" > "$STAMP"
exit 0
