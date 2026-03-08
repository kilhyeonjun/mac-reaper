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

is_non_negative_int() {
  local value="$1"
  [[ "$value" =~ ^[0-9]+$ ]]
}

validate_runtime_config() {
  is_non_negative_int "${REAPER_ORPHAN_MIN_AGE_SEC:-}" || return 1
  is_non_negative_int "${REAPER_GRACE_WAIT_SEC:-}" || return 1
  is_non_negative_int "${REAPER_MAX_KILLS:-}" || return 1
  case "${REAPER_SIGNAL_GRACE:-}" in
    TERM|HUP|INT|QUIT|KILL) ;;
    *) return 1 ;;
  esac
  case "${REAPER_SIGNAL_FORCE:-}" in
    KILL|TERM|HUP|INT|QUIT) ;;
    *) return 1 ;;
  esac
  return 0
}

is_same_reaper_owner() {
  local pid="$1"
  kill -0 "$pid" 2>/dev/null || return 1
  local args
  args="$(ps -p "$pid" -o command= 2>/dev/null | sed 's/^ *//; s/ *$//')"
  [ -n "$args" ] || return 1
  case "$args" in
    *"$REAPER_DIR/reap.sh"*) return 0 ;;
    *) return 1 ;;
  esac
}

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
    if [ -n "$lock_pid" ] && is_same_reaper_owner "$lock_pid"; then
      return 1
    fi

    if [ -n "$lock_pid" ] && ! is_same_reaper_owner "$lock_pid"; then
      rm -rf "$lock_dir"
      if mkdir "$lock_dir" 2>/dev/null; then
        printf '%s\n' "$$" > "$pid_file"
        return 0
      fi
    fi
  else
    rm -rf "$lock_dir"
    if mkdir "$lock_dir" 2>/dev/null; then
      printf '%s\n' "$$" > "$pid_file"
      return 0
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

if ! validate_runtime_config; then
  _log "Invalid config: REAPER_ORPHAN_MIN_AGE_SEC=${REAPER_ORPHAN_MIN_AGE_SEC:-} REAPER_GRACE_WAIT_SEC=${REAPER_GRACE_WAIT_SEC:-} REAPER_SIGNAL_GRACE=${REAPER_SIGNAL_GRACE:-} REAPER_SIGNAL_FORCE=${REAPER_SIGNAL_FORCE:-}"
  exit 2
fi

if ! acquire_lock; then
  _log "Skipped: another_run_in_progress lock=${REAPER_LOCK_DIR:-$HOME/.mac-reaper/run.lock}"
  exit 0
fi

trap release_lock EXIT INT TERM

REAPER_RUN_ID="$(date +%Y%m%dT%H%M%S)-$$"
export REAPER_RUN_ID

# Detect → Reap → Report
targets=$(detect_orphans)
results=$(reap_orphans "$targets")
report "$results"

# Rotate old logs
rotate_logs
