# shellcheck shell=bash
# mac-reaper — orphan process detector
# Sourced by reap.sh

# Get process elapsed time in seconds
# Usage: _get_elapsed_sec <pid>
_get_elapsed_sec() {
  local pid="$1"
  local etime
  etime=$(ps -p "$pid" -o etime= 2>/dev/null | tr -d ' ')
  [ -z "$etime" ] && echo 0 && return

  # Parse etime format: [[dd-]hh:]mm:ss
  local days=0 hours=0 mins=0 secs=0
  if [[ "$etime" == *-* ]]; then
    days="${etime%%-*}"
    etime="${etime#*-}"
  fi

  local IFS=':'
  local parts=()
  read -r -a parts <<< "$etime"
  case ${#parts[@]} in
    3) hours="${parts[0]}"; mins="${parts[1]}"; secs="${parts[2]}" ;;
    2) mins="${parts[0]}"; secs="${parts[1]}" ;;
    1) secs="${parts[0]}" ;;
    *) echo -1; return ;;
  esac

  [[ "$days" =~ ^[0-9]+$ ]] || { echo -1; return; }
  [[ "$hours" =~ ^[0-9]+$ ]] || { echo -1; return; }
  [[ "$mins" =~ ^[0-9]+$ ]] || { echo -1; return; }
  [[ "$secs" =~ ^[0-9]+$ ]] || { echo -1; return; }

  echo $(( 10#$days * 86400 + 10#$hours * 3600 + 10#$mins * 60 + 10#$secs ))
}

_get_ps_start_token() {
  local pid="$1"
  ps -p "$pid" -o lstart= 2>/dev/null | sed 's/^ *//; s/ *$//'
}

# Check if process has child processes
# Usage: _has_children <pid>  → returns 0 (true) or 1 (false)
_has_children() {
  local pid="$1"
  local count
  count=$(pgrep -P "$pid" 2>/dev/null | wc -l | tr -d ' ')
  [ "$count" -gt 0 ]
}

# Detect orphan processes matching REAPER_TARGETS
detect_orphans() {
  local min_age="${REAPER_ORPHAN_MIN_AGE_SEC:-3600}"
  local results=""
  local seen_pids=","

  for target_spec in "${REAPER_TARGETS[@]}"; do
    local pattern="${target_spec%%:*}"
    local condition="${target_spec#*:}"
    [ "$condition" = "$pattern" ] && condition=""

    while read -r ppid pid rss comm; do
      [ -z "${pid:-}" ] && continue
      [ "$comm" = "$pattern" ] || continue
      [ "$ppid" -eq 1 ] || continue

      case "$seen_pids" in
        *",${pid},"*) continue ;;
      esac

      # Check age
      local elapsed
      elapsed=$(_get_elapsed_sec "$pid")
      [ "$elapsed" -lt 0 ] && continue
      [ "$elapsed" -lt "$min_age" ] && continue

      # Check condition
      if [ "$condition" = "children=0" ]; then
        _has_children "$pid" && continue
      fi

      local start_token
      start_token=$(_get_ps_start_token "$pid")
      [ -n "$start_token" ] || continue

      results+="${pid}|${comm}|${rss}|${elapsed}|${condition}|${start_token}"$'\n'
      seen_pids+="${pid},"
    done < <(ps -eo ppid,pid,rss,comm 2>/dev/null)
  done

  printf '%s\n' "$results" | grep -v '^$' || true
}
