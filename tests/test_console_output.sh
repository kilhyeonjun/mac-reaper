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

LOG_DIR="$TMP_DIR/logs"
OUT_FILE="$TMP_DIR/stdout.log"

REAPER_LOG_DIR="$LOG_DIR" REAPER_CONSOLE_LOG=always REAPER_DRY_RUN=1 "$ROOT_DIR/reap.sh" > "$OUT_FILE"

OUT_CONTENT="$(cat "$OUT_FILE")"

assert_contains "RunMeta:" "$OUT_CONTENT" "console output should include RunMeta"
assert_contains "ReasonBuckets:" "$OUT_CONTENT" "console output should include ReasonBuckets"
assert_contains "No orphan processes detected." "$OUT_CONTENT" "console output should include no-orphan summary"

printf 'PASS: test_console_output.sh\n'
