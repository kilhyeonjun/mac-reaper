#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local needle="$1"
  local haystack="$2"
  local msg="$3"
  printf '%s' "$haystack" | grep -Fq "$needle" || fail "$msg"
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

MOCK_BIN="$TMP_DIR/mockbin"
mkdir -p "$MOCK_BIN"

cat > "$MOCK_BIN/ps" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-eo" ]] && [[ "${2:-}" == "ppid,pid,rss,comm" ]]; then
  cat <<'PS'
1 101 2048 opencode
1 202 1024 fzf
PS
  exit 0
fi

if [[ "${1:-}" == "-p" ]]; then
  pid="${2:-}"
  if [[ "${3:-}" == "-o" ]] && [[ "${4:-}" == "etime=" ]]; then
    echo "11-00:00:00"
    exit 0
  fi
  if [[ "${3:-}" == "-o" ]] && [[ "${4:-}" == "lstart=" ]]; then
    echo "Mon Mar 09 01:02:03 2026"
    exit 0
  fi
  if [[ "${3:-}" == "-o" ]] && [[ "${4:-}" == "command=" ]]; then
    if [[ "$pid" == "101" ]]; then
      echo "/opt/homebrew/bin/opencode --session e2e"
    else
      echo "fzf --ansi"
    fi
    exit 0
  fi
  if [[ "${3:-}" == "-o" ]] && [[ "${4:-}" == "comm=" ]]; then
    if [[ "$pid" == "101" ]]; then
      echo "opencode"
    else
      echo "fzf"
    fi
    exit 0
  fi
  if [[ "${3:-}" == "-o" ]] && [[ "${4:-}" == "ppid=" ]]; then
    echo "1"
    exit 0
  fi
fi

exit 1
EOF

cat > "$MOCK_BIN/pgrep" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-P" ]]; then
  exit 0
fi

exit 1
EOF

cat > "$MOCK_BIN/kill" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

flag="${1:-}"
pid="${2:-}"

if [[ "$flag" == "-0" ]]; then
  if [[ "$pid" == "101" ]]; then
    [ -f "$MOCK_KILLED_101" ] && exit 1 || exit 0
  fi
  if [[ "$pid" == "202" ]]; then
    exit 0
  fi
  exit 1
fi

if [[ "$flag" == "-TERM" ]] && [[ "$pid" == "101" ]]; then
  : > "$MOCK_KILLED_101"
  exit 0
fi

if [[ "$flag" == "-KILL" ]] && [[ "$pid" == "101" ]]; then
  : > "$MOCK_KILLED_101"
  exit 0
fi

exit 1
EOF

cat > "$MOCK_BIN/logger" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

chmod +x "$MOCK_BIN/ps" "$MOCK_BIN/pgrep" "$MOCK_BIN/kill" "$MOCK_BIN/logger"

source "$ROOT_DIR/lib/detector.sh"
HASH_101="$(_hash_text "/opt/homebrew/bin/opencode --session e2e")"
HASH_202="$(_hash_text "fzf --ansi")"

LOG_DIR="$TMP_DIR/logs"
LOCK_DIR="$TMP_DIR/lockdir"
KILLED_FLAG="$TMP_DIR/killed-101"

env \
  PATH="$MOCK_BIN:$PATH" \
  REAPER_KILL_CMD="$MOCK_BIN/kill" \
  REAPER_LOG_DIR="$LOG_DIR" \
  REAPER_LOCK_DIR="$LOCK_DIR" \
  REAPER_ORPHAN_MIN_AGE_SEC=0 \
  REAPER_MAX_KILLS=1 \
  REAPER_DRY_RUN=0 \
  MOCK_KILLED_101="$KILLED_FLAG" \
  "$ROOT_DIR/reap.sh"

LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).log"
LOG_CONTENT="$(cat "$LOG_FILE")"

assert_contains "killed: PID=101 comm=opencode rss=2048KB reason=killed" "$LOG_CONTENT" "e2e should kill first target"
assert_contains "skipped: PID=202 comm=fzf rss=1024KB reason=budget_exceeded" "$LOG_CONTENT" "e2e should skip second target by budget"
assert_contains "RunMeta: candidates=2 duration_ms=" "$LOG_CONTENT" "e2e should emit run meta with candidates/duration"
assert_contains "lock_outcome=acquired_new" "$LOG_CONTENT" "e2e lock outcome should be recorded"
assert_contains "config_fp=" "$LOG_CONTENT" "e2e should emit config fingerprint"
assert_contains "ReasonBuckets: budget_exceeded=1 killed=1" "$LOG_CONTENT" "e2e should emit reason bucket counts"
assert_contains "Reaped: 1 killed, 0 failed, 1 skipped, ~2MB freed run_id=" "$LOG_CONTENT" "e2e summary should include expected counts"

[ ! -d "$LOCK_DIR" ] || fail "lock directory should be cleaned after run"
[ -f "$KILLED_FLAG" ] || fail "kill mock should indicate pid 101 was terminated"

printf 'PASS: test_reap_e2e.sh\n'
