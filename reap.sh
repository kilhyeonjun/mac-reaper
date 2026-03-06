#!/usr/bin/env bash
# mac-reaper — entrypoint
# Called by launchd or manually.
# Usage:
#   ./reap.sh              # normal mode
#   REAPER_DRY_RUN=1 ./reap.sh  # dry-run mode

set -euo pipefail

REAPER_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load config and libraries
source "$REAPER_DIR/conf/defaults.conf"
source "$REAPER_DIR/lib/detector.sh"
source "$REAPER_DIR/lib/reaper.sh"
source "$REAPER_DIR/lib/reporter.sh"

# Ensure log directory
_init_log_dir

# Detect → Reap → Report
targets=$(detect_orphans)
results=$(reap_orphans "$targets")
report "$results"

# Rotate old logs
rotate_logs
