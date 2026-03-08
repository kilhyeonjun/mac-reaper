# shellcheck shell=bash
# mac-reaper — kill logic with dry-run support
# Sourced by reap.sh

REAPER_LAST_REASON=""

_get_ps_comm() {
  local pid="$1"
  ps -p "$pid" -o comm= 2>/dev/null | sed 's/^ *//; s/ *$//'
}

_get_ps_ppid() {
  local pid="$1"
  ps -p "$pid" -o ppid= 2>/dev/null | tr -d ' '
}

_get_ps_start_token() {
  local pid="$1"
  ps -p "$pid" -o lstart= 2>/dev/null | sed 's/^ *//; s/ *$//'
}

_validate_candidate() {
  local pid="$1"
  local expected_comm="$2"
  local min_age="$3"
  local condition="$4"
  local expected_start_token="${5:-}"
  local expected_command_hash="${6:-}"

  local current_comm
  current_comm="$(_get_ps_comm "$pid")"
  [ -n "$current_comm" ] || { REAPER_LAST_REASON="missing"; return 1; }

  [ "$current_comm" = "$expected_comm" ] || { REAPER_LAST_REASON="identity_mismatch"; return 1; }

  local current_ppid
  current_ppid="$(_get_ps_ppid "$pid")"
  [ "$current_ppid" = "1" ] || { REAPER_LAST_REASON="not_orphan"; return 1; }

  local current_elapsed
  current_elapsed="$(_get_elapsed_sec "$pid")"
  [ "$current_elapsed" -ge "$min_age" ] || { REAPER_LAST_REASON="too_young"; return 1; }

  if [ "$condition" = "children=0" ] && _has_children "$pid"; then
    REAPER_LAST_REASON="has_children"
    return 1
  fi

  if [ -n "$expected_start_token" ]; then
    local current_start_token
    current_start_token="$(_get_ps_start_token "$pid")"
    [ "$current_start_token" = "$expected_start_token" ] || { REAPER_LAST_REASON="identity_mismatch_start"; return 1; }
  fi

  if [ -n "$expected_command_hash" ]; then
    local current_commandline
    current_commandline="$(_get_ps_commandline "$pid")"
    [ -n "$current_commandline" ] || { REAPER_LAST_REASON="missing_commandline"; return 1; }

    local current_command_hash
    current_command_hash="$(_hash_text "$current_commandline")"
    [ "$current_command_hash" = "$expected_command_hash" ] || { REAPER_LAST_REASON="identity_mismatch_cmdhash"; return 1; }
  fi

  return 0
}

# Kill a single process with grace period
_kill_process() {
  local pid="$1"
  local expected_comm="$2"
  local condition="$3"
  local min_age="$4"
  local expected_start_token="${5:-}"
  local expected_command_hash="${6:-}"
  local grace_signal="${REAPER_SIGNAL_GRACE:-TERM}"
  local force_signal="${REAPER_SIGNAL_FORCE:-KILL}"
  local wait_sec="${REAPER_GRACE_WAIT_SEC:-3}"

  REAPER_LAST_REASON=""

  _validate_candidate "$pid" "$expected_comm" "$min_age" "$condition" "$expected_start_token" "$expected_command_hash" || return 1

  # Verify process still exists
  kill -0 "$pid" 2>/dev/null || { REAPER_LAST_REASON="missing"; return 1; }

  # Graceful shutdown
  kill -"$grace_signal" "$pid" 2>/dev/null || { REAPER_LAST_REASON="term_failed"; return 1; }
  sleep "$wait_sec"

  # Check if it's gone
  if kill -0 "$pid" 2>/dev/null; then
    # Force kill
    kill -"$force_signal" "$pid" 2>/dev/null || { REAPER_LAST_REASON="force_failed"; return 1; }
    sleep 1
    # Final check
    kill -0 "$pid" 2>/dev/null && { REAPER_LAST_REASON="still_running"; return 1; }
  fi

  REAPER_LAST_REASON="killed"
  return 0
}

# Reap detected orphans
reap_orphans() {
  local detections="$1"
  local dry_run="${REAPER_DRY_RUN:-0}"
  local min_age="${REAPER_ORPHAN_MIN_AGE_SEC:-3600}"
  local max_kills="${REAPER_MAX_KILLS:-200}"
  local results=""
  local killed_count=0

  while IFS='|' read -r pid comm rss _elapsed condition start_token command_hash; do
    [ -z "$pid" ] && continue

    if [ "$dry_run" -eq 1 ]; then
      results+="${pid}|${comm}|${rss}|dry-run|would_kill"$'\n'
      continue
    fi

    if [ "$killed_count" -ge "$max_kills" ]; then
      results+="${pid}|${comm}|${rss}|skipped|budget_exceeded"$'\n'
      continue
    fi

    if _kill_process "$pid" "$comm" "$condition" "$min_age" "$start_token" "$command_hash"; then
      results+="${pid}|${comm}|${rss}|killed|${REAPER_LAST_REASON}"$'\n'
      killed_count=$((killed_count + 1))
    else
      results+="${pid}|${comm}|${rss}|failed|${REAPER_LAST_REASON:-unknown}"$'\n'
    fi
  done <<< "$detections"

  echo "$results" | grep -v '^$' || true
}
