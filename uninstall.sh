#!/usr/bin/env bash
# mac-reaper — uninstall launchd agent
set -euo pipefail

LABEL="net.kilhyeonjun.mac-reaper"
PLIST_DST="$HOME/Library/LaunchAgents/net.kilhyeonjun.mac-reaper.plist"

echo "mac-reaper uninstaller"
echo "======================"

# 1. Unload agent
if launchctl print "gui/$(id -u)/$LABEL" &>/dev/null; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
  echo "✓ LaunchAgent unloaded"
else
  echo "- LaunchAgent not loaded (skipping)"
fi

# 2. Remove plist
if [ -f "$PLIST_DST" ]; then
  rm "$PLIST_DST"
  echo "✓ Plist removed: $PLIST_DST"
else
  echo "- Plist not found (skipping)"
fi

echo ""
echo "✅ Uninstalled. Logs kept at ~/.mac-reaper/logs/"
echo "   To remove logs: rm -rf ~/.mac-reaper"
