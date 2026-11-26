#!/bin/bash
# Sets up the hourly automatic install of Sloth Cinema on your iPhone (see autoinstall.sh).
#   bash scripts/mac/install-autoinstall.sh            # turn it on (and run it once now)
#   bash scripts/mac/install-autoinstall.sh --remove   # turn it off
set -euo pipefail
LABEL="com.benjaminrenard.slothcinema.autoinstall"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SCRIPT="$(cd "$(dirname "$0")" && pwd)/autoinstall.sh"
LOG="$HOME/Library/Logs/SlothCinema-autoinstall.log"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
if [ "${1:-}" = "--remove" ]; then
  rm -f "$PLIST"
  echo "Automatic install turned off."
  exit 0
fi

mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
chmod +x "$SCRIPT"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>$SCRIPT</string></array>
  <key>StartInterval</key><integer>3600</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin</string></dict>
</dict>
</plist>
PLIST
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Automatic install is on: every hour, and when you log in. Log: $LOG"
echo "First run in progress; follow it with:  tail -f \"$LOG\""
