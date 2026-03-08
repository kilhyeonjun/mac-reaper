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
  local parts=($etime)
  case ${#parts[@]} in
    3) hours="${parts[0]}"; mins="${parts[1]}"; secs="${parts[2]}" ;;
    2) mins="${parts[0]}"; secs="${parts[1]}" ;;
    1) secs="${parts[0]}" ;;
  esac

  echo $(( 10#$days * 86400 + 10#$hours * 3600 + 10#$mins * 60 + 10#$secs ))
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
# Output: pid|comm|rss_kb|elapsed_sec  (one per line)
detect_orphans() {
  local min_age="${REAPER_ORPHAN_MIN_AGE_SEC:-3600}"
  local results=""

  for target_spec in "${REAPER_TARGETS[@]}"; do
    local pattern="${target_spec%%:*}"
    local condition="${target_spec#*:}"
    [ "$condition" = "$pattern" ] && condition=""

    # Find all PPID=1 processes matching the pattern
    while IFS= read -r line; do
      [ -z "$line" ] && continue

      local ppid pid rss comm
      ppid=$(echo "$line" | awk '{print $1}')
      pid=$(echo "$line" | awk '{print $2}')
      rss=$(echo "$line" | awk '{print $3}')
      comm=$(echo "$line" | awk '{$1=$2=$3=""; print}' | sed 's/^ *//')

      # Must be orphaned (PPID=1)
      [ "$ppid" -ne 1 ] && continue

      # Check age
      local elapsed
      elapsed=$(_get_elapsed_sec "$pid")
      [ "$elapsed" -lt "$min_age" ] && continue

      # Check condition
      if [ "$condition" = "children=0" ]; then
        _has_children "$pid" && continue
      fi

      results+="${pid}|${comm}|${rss}|${elapsed}"$'\n'
    done < <(ps -eo ppid,pid,rss,comm 2>/dev/null | grep "$pattern")
  done

  echo "$results" | grep -v '^$' || true
}
