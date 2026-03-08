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

acquire_lock() {
  local lock_dir="${REAPER_LOCK_DIR:-$HOME/.mac-reaper/run.lock}"
  local pid_file="$lock_dir/pid"

  if mkdir "$lock_dir" 2>/dev/null; then
    printf '%s\n' "$$" > "$pid_file"
    return 0
  fi

  if [ -f "$pid_file" ]; then
    local lock_pid
    lock_pid="$(tr -d ' ' < "$pid_file" 2>/dev/null || true)"
    if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
      rm -rf "$lock_dir"
      if mkdir "$lock_dir" 2>/dev/null; then
        printf '%s\n' "$$" > "$pid_file"
        return 0
      fi
    fi
  fi

  return 1
}

release_lock() {
  local lock_dir="${REAPER_LOCK_DIR:-$HOME/.mac-reaper/run.lock}"
  rm -f "$lock_dir/pid" 2>/dev/null || true
  rmdir "$lock_dir" 2>/dev/null || true
}

# Ensure log directory
_init_log_dir

if ! acquire_lock; then
  _log "Skipped: another_run_in_progress lock=${REAPER_LOCK_DIR:-$HOME/.mac-reaper/run.lock}"
  exit 0
fi

trap release_lock EXIT INT TERM

# Detect → Reap → Report
targets=$(detect_orphans)
results=$(reap_orphans "$targets")
report "$results"

# Rotate old logs
rotate_logs
