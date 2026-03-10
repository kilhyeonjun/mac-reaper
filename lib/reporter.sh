# shellcheck shell=bash
# mac-reaper — logging and reporting
# Sourced by reap.sh

# Ensure log directory exists
_init_log_dir() {
  local log_dir="${REAPER_LOG_DIR:-$HOME/.mac-reaper/logs}"
  mkdir -p "$log_dir"
}

# Get today's log file path
_log_file() {
  echo "${REAPER_LOG_DIR:-$HOME/.mac-reaper/logs}/$(date +%Y-%m-%d).log"
}

# Write a line to the log file
_log() {
  local msg="$1"
  local timestamp
  local line
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  line="[$timestamp] $msg"
  echo "$line" >> "$(_log_file)"

  case "${REAPER_CONSOLE_LOG:-auto}" in
    always)
      printf '%s\n' "$line"
      ;;
    never)
      ;;
    auto|*)
      if [ -t 1 ]; then
        printf '%s\n' "$line"
      fi
      ;;
  esac
}

# Report reap results
report() {
  local results="$1"
  local run_id="${REAPER_RUN_ID:-manual}"
  local run_duration_ms="${REAPER_RUN_DURATION_MS:-0}"
  local candidates_detected="${REAPER_CANDIDATES_DETECTED:-0}"
  local lock_outcome="${REAPER_LOCK_OUTCOME:-unknown}"
  local config_fingerprint="${REAPER_CONFIG_FINGERPRINT:-unknown}"
  local run_status="${REAPER_RUN_STATUS:-completed}"
  local failure_reason="${REAPER_FAILURE_REASON:-none}"

  local killed=0 failed=0 dryrun=0 skipped=0
  local total_rss=0
  local reason_rows=""

  _log "─── mac-reaper run id=${run_id} ───"
  _log "RunMeta: candidates=${candidates_detected} duration_ms=${run_duration_ms} lock_outcome=${lock_outcome} run_status=${run_status} failure_reason=${failure_reason} config_fp=${config_fingerprint}"

  [ -z "$results" ] && {
    _log "ReasonBuckets: none"
    _log "No orphan processes detected."
    return
  }

  while IFS='|' read -r pid comm rss status reason; do
    [ -z "$pid" ] && continue
    _log "  $status: PID=$pid comm=$comm rss=${rss}KB reason=${reason:-n/a}"
    reason_rows+="${reason:-unknown}"$'\n'

    case "$status" in
      killed)  ((killed++)); ((total_rss += rss)) ;;
      failed)  ((failed++)) ;;
      dry-run) ((dryrun++)); ((total_rss += rss)) ;;
      skipped) ((skipped++)) ;;
    esac
  done <<< "$results"

  local summary
  if [ "$dryrun" -gt 0 ]; then
    summary="DRY-RUN: ${dryrun} orphans detected (~$((total_rss / 1024))MB) run_id=${run_id}"
  else
    summary="Reaped: ${killed} killed, ${failed} failed, ${skipped} skipped, ~$((total_rss / 1024))MB freed run_id=${run_id}"
  fi

  reason_buckets="$(printf '%s' "$reason_rows" | grep -v '^$' | sort | uniq -c | awk '{printf "%s=%d ", $2, $1}')"
  reason_buckets="${reason_buckets% }"
  [ -n "$reason_buckets" ] || reason_buckets="none"
  _log "ReasonBuckets: ${reason_buckets}"

  _log "$summary"

  # Also log to macOS system log
  logger -t mac-reaper "$summary"
}

# Rotate old log files
rotate_logs() {
  local log_dir="${REAPER_LOG_DIR:-$HOME/.mac-reaper/logs}"
  local retain_days="${REAPER_LOG_RETAIN_DAYS:-30}"

  find "$log_dir" -name "*.log" -mtime +"$retain_days" -delete 2>/dev/null

  local launchd_stdout="$HOME/.mac-reaper/launchd-stdout.log"
  local launchd_stderr="$HOME/.mac-reaper/launchd-stderr.log"
  if [ -f "$launchd_stdout" ]; then
    find "$launchd_stdout" -mtime +"$retain_days" -delete 2>/dev/null
  fi
  if [ -f "$launchd_stderr" ]; then
    find "$launchd_stderr" -mtime +"$retain_days" -delete 2>/dev/null
  fi

  return 0
}
