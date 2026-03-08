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
owner_pid=""
sleeper_pid=""
trap '[ -n "${owner_pid:-}" ] && kill "$owner_pid" 2>/dev/null || true; [ -n "${sleeper_pid:-}" ] && kill "$sleeper_pid" 2>/dev/null || true; rm -rf "$TMP_DIR"' EXIT

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

  python3 -c 'import time; time.sleep(30)' "$ROOT_DIR/reap.sh" &
  owner_pid=$!

  printf '%s\n' "$owner_pid" > "$lock_dir/pid"

  local log
  log="$(run_once "$lock_dir" "$log_dir")"

  assert_contains "Skipped: another_run_in_progress" "$log" "live pid lock should skip run"

  kill "$owner_pid" 2>/dev/null || true
  wait "$owner_pid" 2>/dev/null || true
  owner_pid=""
}

test_live_unrelated_pid_should_recover_lock() {
  local case_dir="$TMP_DIR/case-live-unrelated"
  local lock_dir="$case_dir/run.lock"
  local log_dir="$case_dir/logs"
  mkdir -p "$lock_dir" "$log_dir"

  sleep 30 &
  sleeper_pid=$!

  printf '%s\n' "$sleeper_pid" > "$lock_dir/pid"

  local log
  log="$(run_once "$lock_dir" "$log_dir")"

  assert_contains "Skipped: another_run_in_progress" "$log" "ambiguous live pid should fail closed and skip"

  kill "$sleeper_pid" 2>/dev/null || true
  wait "$sleeper_pid" 2>/dev/null || true
  sleeper_pid=""
}

test_missing_pid_file_should_recover_lock
test_dead_pid_should_recover_lock
test_live_pid_should_skip
test_live_unrelated_pid_should_recover_lock

printf 'PASS: test_lock.sh\n'
