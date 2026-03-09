#!/usr/bin/env bash
# mac-reaper — entrypoint
# Called by launchd or manually.
# Usage:
#   ./reap.sh              # normal mode
#   REAPER_DRY_RUN=1 ./reap.sh  # dry-run mode

set -euo pipefail

REAPER_DIR="$(cd "$(dirname "$0")" && pwd)"

now_ms() {
  python3 - <<'PY'
import time
print(time.time_ns() // 1_000_000)
PY
}

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
  local expected_start_token="${2:-}"
  kill -0 "$pid" 2>/dev/null || return 1
  local args
  args="$(ps -p "$pid" -o command= 2>/dev/null | sed 's/^ *//; s/ *$//')"
  [ -n "$args" ] || return 1
  case "$args" in
    *"$REAPER_DIR/reap.sh"*|*"/bin/bash $REAPER_DIR/reap.sh"*) return 0 ;;
    *) return 1 ;;
  esac

  if [ -n "$expected_start_token" ]; then
    local current_start_token
    current_start_token="$(ps -p "$pid" -o lstart= 2>/dev/null | sed 's/^ *//; s/ *$//')"
    [ "$current_start_token" = "$expected_start_token" ] || return 1
  fi

  return 0
}

write_lock_meta() {
  local lock_dir="$1"
  local token="$2"
  umask 077
  {
    printf 'pid=%s\n' "$$"
    printf 'uid=%s\n' "$(id -u)"
    printf 'reaper_dir=%s\n' "$REAPER_DIR"
    printf 'start_token=%s\n' "$(ps -p $$ -o lstart= 2>/dev/null | sed 's/^ *//; s/ *$//')"
    printf 'token=%s\n' "$token"
  } > "$lock_dir/meta"
}

read_lock_meta() {
  local lock_dir="$1"
  local meta_file="$lock_dir/meta"
  LOCK_META_UID=""
  LOCK_META_PID=""
  LOCK_META_REAPER_DIR=""
  LOCK_META_START_TOKEN=""
  LOCK_META_TOKEN=""

  [ -f "$meta_file" ] || return 1

  while IFS='=' read -r key value; do
    case "$key" in
      pid) LOCK_META_PID="$value" ;;
      uid) LOCK_META_UID="$value" ;;
      reaper_dir) LOCK_META_REAPER_DIR="$value" ;;
      start_token) LOCK_META_START_TOKEN="$value" ;;
      token) LOCK_META_TOKEN="$value" ;;
    esac
  done < "$meta_file"

  [ -n "$LOCK_META_UID" ] && [ -n "$LOCK_META_PID" ] && [ -n "$LOCK_META_REAPER_DIR" ] && [ -n "$LOCK_META_START_TOKEN" ] && [ -n "$LOCK_META_TOKEN" ]
}

acquire_lock() {
  local lock_dir="${REAPER_LOCK_DIR:-$HOME/.mac-reaper/run.lock}"
  local pid_file="$lock_dir/pid"
  local lock_token
  lock_token="$$-$(date +%s)"

  if mkdir "$lock_dir" 2>/dev/null; then
    printf '%s\n' "$$" > "$pid_file"
    write_lock_meta "$lock_dir" "$lock_token"
    REAPER_LOCK_OUTCOME="acquired_new"
    return 0
  fi

  if [ -f "$pid_file" ]; then
    local lock_pid
    lock_pid="$(tr -d ' ' < "$pid_file" 2>/dev/null || true)"

    if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
      if read_lock_meta "$lock_dir" && \
         [ "$LOCK_META_UID" = "$(id -u)" ] && \
         [ "$LOCK_META_PID" = "$lock_pid" ] && \
         [ "$LOCK_META_REAPER_DIR" = "$REAPER_DIR" ] && \
         is_same_reaper_owner "$lock_pid" "$LOCK_META_START_TOKEN"; then
        REAPER_LOCK_OUTCOME="skip_live_owner"
        return 1
      fi

      REAPER_LOCK_OUTCOME="skip_ambiguous_live_holder"
      return 1
    fi

    if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
      rm -rf "$lock_dir"
      if mkdir "$lock_dir" 2>/dev/null; then
        printf '%s\n' "$$" > "$pid_file"
        write_lock_meta "$lock_dir" "$lock_token"
        REAPER_LOCK_OUTCOME="recovered_stale_pid"
        return 0
      fi
    fi
  else
    rm -rf "$lock_dir"
    if mkdir "$lock_dir" 2>/dev/null; then
      printf '%s\n' "$$" > "$pid_file"
      write_lock_meta "$lock_dir" "$lock_token"
      REAPER_LOCK_OUTCOME="recovered_missing_pid"
      return 0
    fi
  fi

  REAPER_LOCK_OUTCOME="lock_error"
  return 1
}

release_lock() {
  local lock_dir="${REAPER_LOCK_DIR:-$HOME/.mac-reaper/run.lock}"
  rm -f "$lock_dir/pid" 2>/dev/null || true
  rm -f "$lock_dir/meta" 2>/dev/null || true
  rmdir "$lock_dir" 2>/dev/null || true
}

# Ensure log directory
_init_log_dir

RUN_START_MS="$(now_ms)"
REAPER_RUN_ID="$(date +%Y%m%dT%H%M%S)-$$"
export REAPER_RUN_ID

cfg_targets="$(printf '%s;' "${REAPER_TARGETS[@]}")"
cfg_source="min_age=${REAPER_ORPHAN_MIN_AGE_SEC:-};max_kills=${REAPER_MAX_KILLS:-};grace_signal=${REAPER_SIGNAL_GRACE:-};force_signal=${REAPER_SIGNAL_FORCE:-};grace_wait=${REAPER_GRACE_WAIT_SEC:-};retain_days=${REAPER_LOG_RETAIN_DAYS:-};targets=${cfg_targets}"
REAPER_CONFIG_FINGERPRINT="$(_hash_text "$cfg_source")"
export REAPER_CONFIG_FINGERPRINT

if ! validate_runtime_config; then
  REAPER_CANDIDATES_DETECTED=0
  REAPER_RUN_DURATION_MS="$(( $(now_ms) - RUN_START_MS ))"
  REAPER_RUN_STATUS="invalid_config"
  REAPER_FAILURE_REASON="invalid_config"
  REAPER_LOCK_OUTCOME="not_acquired_invalid_config"
  export REAPER_CANDIDATES_DETECTED REAPER_RUN_DURATION_MS REAPER_RUN_STATUS REAPER_FAILURE_REASON REAPER_LOCK_OUTCOME
  report ""
  rotate_logs
  _log "Invalid config: REAPER_ORPHAN_MIN_AGE_SEC=${REAPER_ORPHAN_MIN_AGE_SEC:-} REAPER_GRACE_WAIT_SEC=${REAPER_GRACE_WAIT_SEC:-} REAPER_SIGNAL_GRACE=${REAPER_SIGNAL_GRACE:-} REAPER_SIGNAL_FORCE=${REAPER_SIGNAL_FORCE:-}"
  exit 2
fi

if ! acquire_lock; then
  REAPER_CANDIDATES_DETECTED=0
  REAPER_RUN_DURATION_MS="$(( $(now_ms) - RUN_START_MS ))"
  REAPER_RUN_STATUS="skipped_by_lock"
  REAPER_FAILURE_REASON="${REAPER_LOCK_OUTCOME:-lock_unavailable}"
  export REAPER_CANDIDATES_DETECTED REAPER_RUN_DURATION_MS REAPER_RUN_STATUS REAPER_FAILURE_REASON REAPER_LOCK_OUTCOME
  report ""
  rotate_logs
  _log "Skipped: another_run_in_progress lock=${REAPER_LOCK_DIR:-$HOME/.mac-reaper/run.lock}"
  exit 0
fi

trap release_lock EXIT INT TERM

# Detect → Reap → Report
targets=$(detect_orphans)
CANDIDATES_DETECTED="$(printf '%s\n' "$targets" | awk 'NF{c++} END{print c+0}')"
REAPER_CANDIDATES_DETECTED="$CANDIDATES_DETECTED"
export REAPER_CANDIDATES_DETECTED

results=$(reap_orphans "$targets")

RUN_END_MS="$(now_ms)"
REAPER_RUN_DURATION_MS="$((RUN_END_MS - RUN_START_MS))"
export REAPER_RUN_DURATION_MS

export REAPER_LOCK_OUTCOME="${REAPER_LOCK_OUTCOME:-unknown}"
REAPER_RUN_STATUS="completed"
REAPER_FAILURE_REASON="none"
export REAPER_RUN_STATUS REAPER_FAILURE_REASON

report "$results"

# Rotate old logs
rotate_logs
