# mac-reaper — kill logic with dry-run support
# Sourced by reap.sh

# Kill a single process with grace period
# Usage: _kill_process <pid>
# Returns: 0 if killed, 1 if failed
_kill_process() {
  local pid="$1"
  local grace_signal="${REAPER_SIGNAL_GRACE:-TERM}"
  local force_signal="${REAPER_SIGNAL_FORCE:-KILL}"
  local wait_sec="${REAPER_GRACE_WAIT_SEC:-3}"

  # Verify process still exists
  kill -0 "$pid" 2>/dev/null || return 1

  # Graceful shutdown
  kill -"$grace_signal" "$pid" 2>/dev/null
  sleep "$wait_sec"

  # Check if it's gone
  if kill -0 "$pid" 2>/dev/null; then
    # Force kill
    kill -"$force_signal" "$pid" 2>/dev/null
    sleep 1
    # Final check
    kill -0 "$pid" 2>/dev/null && return 1
  fi

  return 0
}

# Reap detected orphans
# Input: output from detect_orphans (pid|comm|rss|elapsed per line)
# Output: pid|comm|rss|status  (one per line, status=killed|skipped|failed)
reap_orphans() {
  local detections="$1"
  local dry_run="${REAPER_DRY_RUN:-0}"
  local results=""

  while IFS='|' read -r pid comm rss elapsed; do
    [ -z "$pid" ] && continue

    if [ "$dry_run" -eq 1 ]; then
      results+="${pid}|${comm}|${rss}|dry-run"$'\n'
      continue
    fi

    if _kill_process "$pid"; then
      results+="${pid}|${comm}|${rss}|killed"$'\n'
    else
      results+="${pid}|${comm}|${rss}|failed"$'\n'
    fi
  done <<< "$detections"

  echo "$results" | grep -v '^$' || true
}
