#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

LOCK_DIR="$TMP_DIR/run.lock"
LOG_DIR="$TMP_DIR/logs"
mkdir -p "$LOCK_DIR" "$LOG_DIR"
printf '%s\n' "$$" > "$LOCK_DIR/pid"

REAPER_LOG_DIR="$LOG_DIR" REAPER_LOCK_DIR="$LOCK_DIR" REAPER_DRY_RUN=1 "$ROOT_DIR/reap.sh"

LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).log"
[ -f "$LOG_FILE" ] || fail "lock skip run should still log a message"

grep -Fq "Skipped: another_run_in_progress" "$LOG_FILE" || fail "lock skip message should be logged"

printf 'PASS: test_lock.sh\n'
