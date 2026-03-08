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

REAPER_LOG_DIR="$TMP_DIR/logs"
REAPER_LOG_RETAIN_DAYS=0
mkdir -p "$REAPER_LOG_DIR"

source "$ROOT_DIR/lib/reporter.sh"

test_report_empty_results_logs_no_orphans() {
  REAPER_RUN_ID="run-empty"
  REAPER_RUN_DURATION_MS=7
  REAPER_CANDIDATES_DETECTED=0
  REAPER_LOCK_OUTCOME="acquired_new"
  REAPER_CONFIG_FINGERPRINT="cfg-empty"
  report ""

  local log
  log="$(cat "$REAPER_LOG_DIR/$(date +%Y-%m-%d).log")"
  assert_contains "RunMeta: candidates=0 duration_ms=7 lock_outcome=acquired_new config_fp=cfg-empty" "$log" "empty result should still emit run metrics"
  assert_contains "ReasonBuckets: none" "$log" "empty result should emit empty reason buckets"
  assert_contains "No orphan processes detected." "$log" "empty result should log no-orphans message"
}

test_report_mixed_results_summary_with_run_id() {
  REAPER_RUN_ID="run-mixed"
  REAPER_RUN_DURATION_MS=123
  REAPER_CANDIDATES_DETECTED=4
  REAPER_LOCK_OUTCOME="acquired_new"
  REAPER_CONFIG_FINGERPRINT="cfg123"
  local fixture
  fixture=$'10|opencode|2048|killed|killed\n20|fzf|1024|failed|identity_mismatch\n30|/bin/zsh|512|skipped|budget_exceeded\n40|git|512|dry-run|would_kill'

  report "$fixture"

  local log
  log="$(cat "$REAPER_LOG_DIR/$(date +%Y-%m-%d).log")"

  assert_contains "mac-reaper run id=run-mixed" "$log" "run header should include run_id"
  assert_contains "RunMeta: candidates=4 duration_ms=123 lock_outcome=acquired_new config_fp=cfg123" "$log" "run meta should include extended metrics"
  assert_contains "ReasonBuckets: budget_exceeded=1 identity_mismatch=1 killed=1 would_kill=1" "$log" "reason buckets should be aggregated"
  assert_contains "DRY-RUN: 1 orphans detected (~2MB) run_id=run-mixed" "$log" "dry-run summary should include run_id and MB"
}

test_rotate_logs_removes_old_launchd_logs() {
  local mac_reaper_dir="$TMP_DIR/.mac-reaper"
  mkdir -p "$mac_reaper_dir"

  local old_stdout="$mac_reaper_dir/launchd-stdout.log"
  local old_stderr="$mac_reaper_dir/launchd-stderr.log"

  : > "$old_stdout"
  : > "$old_stderr"
  touch -t 202001010101 "$old_stdout" "$old_stderr"

  HOME="$TMP_DIR" rotate_logs

  [ ! -f "$old_stdout" ] || fail "rotate_logs should remove old launchd stdout log"
  [ ! -f "$old_stderr" ] || fail "rotate_logs should remove old launchd stderr log"
}

test_report_empty_results_logs_no_orphans
test_report_mixed_results_summary_with_run_id
test_rotate_logs_removes_old_launchd_logs

printf 'PASS: test_reporter.sh\n'
