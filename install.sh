#!/usr/bin/env bash
# mac-reaper — install launchd agent
set -euo pipefail

REAPER_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST_SRC="$REAPER_DIR/launchd/net.kilhyeonjun.mac-reaper.plist"
PLIST_DST="$HOME/Library/LaunchAgents/net.kilhyeonjun.mac-reaper.plist"
LABEL="net.kilhyeonjun.mac-reaper"

echo "mac-reaper installer"
echo "===================="

# 1. Make reap.sh executable
chmod +x "$REAPER_DIR/reap.sh"
echo "✓ reap.sh executable"

# 2. Create log directory
mkdir -p "$HOME/.mac-reaper/logs"
echo "✓ Log directory: ~/.mac-reaper/logs"

# 3. Generate plist with actual paths
sed \
  -e "s|__REAPER_DIR__|$REAPER_DIR|g" \
  -e "s|__HOME__|$HOME|g" \
  "$PLIST_SRC" > "$PLIST_DST"
echo "✓ Plist installed: $PLIST_DST"

# 4. Unload if already loaded (ignore errors)
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true

# 5. Load the agent
launchctl bootstrap "gui/$(id -u)" "$PLIST_DST"
echo "✓ LaunchAgent loaded: $LABEL"

# 6. Verify
if launchctl print "gui/$(id -u)/$LABEL" &>/dev/null; then
  echo ""
  echo "✅ Installation complete!"
  echo "   Runs every 3 hours + at login"
  echo "   Logs: ~/.mac-reaper/logs/"
  echo ""
  echo "   Manual run:    $REAPER_DIR/reap.sh"
  echo "   Dry-run:       REAPER_DRY_RUN=1 $REAPER_DIR/reap.sh"
  echo "   Uninstall:     $REAPER_DIR/uninstall.sh"
else
  echo "⚠ LaunchAgent loaded but verification failed. Check manually:"
  echo "  launchctl list | grep mac-reaper"
fi
