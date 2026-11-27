#!/bin/bash
# Run by Xcode after each build (scheme post-action): installs the app just built on the
# other iPhones in SLOTH_PHONES that are connected (cable or Wi-Fi), so pressing ▶ for one
# phone updates them all. Runs in the background; log in ~/Library/Logs/SlothCinema-install.log.
APP="$1"            # the .app Xcode just built
SKIP="$2"           # the device Xcode is about to install on itself
PHONES="${SLOTH_PHONES:-iPhone de Ben,iPhone de Camille Devisme}"
[ -d "$APP" ] || exit 0
notify() { /usr/bin/osascript -e "display notification \"$1\" with title \"Sloth Cinema\"" >/dev/null 2>&1 || true; }
DEVICES="$(xcrun xctrace list devices 2>/dev/null | awk '/^== Devices ==/{f=1;next} /^==/{f=0} f')"
IFS=',' read -ra NAMES <<< "$PHONES"
for PHONE in "${NAMES[@]}"; do
  PHONE="$(echo "$PHONE" | sed -E 's/^ +| +$//g')"
  UDID="$(echo "$DEVICES" | grep -F "$PHONE" | head -1 | sed -E 's/.*\(([0-9A-Fa-f-]{20,})\)[[:space:]]*$/\1/')"
  [ -z "$UDID" ] && { echo "$(date '+%H:%M') $PHONE not connected"; continue; }
  [ "$UDID" = "$SKIP" ] && continue
  if xcrun devicectl device install app --device "$UDID" "$APP" >/dev/null 2>&1; then
    echo "$(date '+%H:%M') installed on $PHONE"; notify "Also installed on $PHONE."
  else
    echo "$(date '+%H:%M') install on $PHONE failed (unlocked? trusted?)"
  fi
done
