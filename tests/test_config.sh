#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

LOG_DIR="$TMP_DIR/logs"
mkdir -p "$LOG_DIR"

set +e
REAPER_LOG_DIR="$LOG_DIR" REAPER_DRY_RUN=1 REAPER_GRACE_WAIT_SEC="abc" "$ROOT_DIR/reap.sh" >/tmp/mac-reaper-test-config.out 2>/tmp/mac-reaper-test-config.err
status=$?
set -e

[ "$status" -ne 0 ] || fail "invalid numeric config should fail fast with non-zero exit"

LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).log"
[ -f "$LOG_FILE" ] || fail "invalid config should still write a log entry"
grep -Fq "Invalid config" "$LOG_FILE" || fail "invalid config log message should be present"

printf 'PASS: test_config.sh\n'
