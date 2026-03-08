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
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] $msg" >> "$(_log_file)"
}

# Report reap results
report() {
  local results="$1"
  local run_id="${REAPER_RUN_ID:-manual}"

  [ -z "$results" ] && {
    _log "No orphan processes detected."
    return
  }

  local killed=0 failed=0 dryrun=0 skipped=0
  local total_rss=0

  _log "─── mac-reaper run id=${run_id} ───"

  while IFS='|' read -r pid comm rss status reason; do
    [ -z "$pid" ] && continue
    _log "  $status: PID=$pid comm=$comm rss=${rss}KB reason=${reason:-n/a}"

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
  [ -f "$launchd_stdout" ] && find "$launchd_stdout" -mtime +"$retain_days" -delete 2>/dev/null
  [ -f "$launchd_stderr" ] && find "$launchd_stderr" -mtime +"$retain_days" -delete 2>/dev/null
}
