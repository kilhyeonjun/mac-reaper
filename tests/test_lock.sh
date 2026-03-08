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

assert_not_contains() {
  local needle="$1"
  local haystack="$2"
  local msg="$3"
  if printf '%s' "$haystack" | grep -Fq "$needle"; then
    fail "$msg"
  fi
}

run_once() {
  local lock_dir="$1"
  local log_dir="$2"
  REAPER_LOG_DIR="$log_dir" REAPER_LOCK_DIR="$lock_dir" REAPER_DRY_RUN=1 "$ROOT_DIR/reap.sh"
  cat "$log_dir/$(date +%Y-%m-%d).log"
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

test_missing_pid_file_should_recover_lock() {
  local case_dir="$TMP_DIR/case-missing-pid"
  local lock_dir="$case_dir/run.lock"
  local log_dir="$case_dir/logs"
  mkdir -p "$lock_dir" "$log_dir"

  local log
  log="$(run_once "$lock_dir" "$log_dir")"

  assert_not_contains "Skipped: another_run_in_progress" "$log" "missing pid file lock should be treated as stale and recovered"
  assert_contains "No orphan processes detected." "$log" "recovered run should proceed normally"
}

test_dead_pid_should_recover_lock() {
  local case_dir="$TMP_DIR/case-dead-pid"
  local lock_dir="$case_dir/run.lock"
  local log_dir="$case_dir/logs"
  mkdir -p "$lock_dir" "$log_dir"
  printf '%s\n' "999999" > "$lock_dir/pid"

  local log
  log="$(run_once "$lock_dir" "$log_dir")"

  assert_not_contains "Skipped: another_run_in_progress" "$log" "dead pid lock should be recovered"
  assert_contains "No orphan processes detected." "$log" "recovered run should proceed normally"
}

test_live_pid_should_skip() {
  local case_dir="$TMP_DIR/case-live-pid"
  local lock_dir="$case_dir/run.lock"
  local log_dir="$case_dir/logs"
  mkdir -p "$lock_dir" "$log_dir"
  printf '%s\n' "$$" > "$lock_dir/pid"

  local log
  log="$(run_once "$lock_dir" "$log_dir")"

  assert_contains "Skipped: another_run_in_progress" "$log" "live pid lock should skip run"
}

test_missing_pid_file_should_recover_lock
test_dead_pid_should_recover_lock
test_live_pid_should_skip

printf 'PASS: test_lock.sh\n'
