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

source "$ROOT_DIR/lib/detector.sh"
source "$ROOT_DIR/lib/reaper.sh"

test_reap_orphans_dry_run() {
  REAPER_DRY_RUN=1
  REAPER_ORPHAN_MIN_AGE_SEC=0
  local detections
  detections=$'10|opencode|100|999|children=0|Mon Mar 09 01:02:03 2026|hash10\n20|fzf|200|999||Mon Mar 09 01:02:03 2026|hash20'

  local out
  out="$(reap_orphans "$detections")"

  assert_contains "10|opencode|100|dry-run|would_kill" "$out" "dry-run should mark first process"
  assert_contains "20|fzf|200|dry-run|would_kill" "$out" "dry-run should mark second process"
}

test_reap_orphans_status_mapping() {
  REAPER_DRY_RUN=0
  REAPER_ORPHAN_MIN_AGE_SEC=0
  _kill_process() {
    if [ "$1" = "10" ]; then
      REAPER_LAST_REASON="killed"
      return 0
    fi
    REAPER_LAST_REASON="identity_mismatch"
    return 1
  }

  local detections
  detections=$'10|opencode|100|999|children=0|Mon Mar 09 01:02:03 2026|hash10\n20|fzf|200|999||Mon Mar 09 01:02:03 2026|hash20'

  local out
  out="$(reap_orphans "$detections")"

  assert_contains "10|opencode|100|killed|killed" "$out" "successful kill should be marked killed with reason"
  assert_contains "20|fzf|200|failed|identity_mismatch" "$out" "failed kill should include reason"
}

test_validate_candidate_requires_start_token_match() {
  _get_ps_comm() { echo "opencode"; }
  _get_ps_ppid() { echo "1"; }
  _get_elapsed_sec() { echo "999"; }
  _has_children() { return 1; }
  _get_ps_start_token() { echo "Mon Mar 09 01:02:03 2026"; }
  _get_ps_commandline() { echo "/opt/homebrew/bin/opencode --session alpha"; }
  _hash_text() { echo "hash-alpha"; }

  if _validate_candidate "10" "opencode" "0" "children=0" "Mon Mar 09 11:22:33 2026" "hash-alpha"; then
    fail "_validate_candidate should fail when start token mismatches"
  fi

  assert_contains "identity_mismatch_start" "$REAPER_LAST_REASON" "reason should indicate start-token mismatch"
}

test_validate_candidate_requires_command_hash_match() {
  _get_ps_comm() { echo "opencode"; }
  _get_ps_ppid() { echo "1"; }
  _get_elapsed_sec() { echo "999"; }
  _has_children() { return 1; }
  _get_ps_start_token() { echo "Mon Mar 09 01:02:03 2026"; }
  _get_ps_commandline() { echo "/opt/homebrew/bin/opencode --session alpha"; }
  _hash_text() { echo "hash-alpha"; }

  if _validate_candidate "10" "opencode" "0" "children=0" "Mon Mar 09 01:02:03 2026" "hash-other"; then
    fail "_validate_candidate should fail when command hash mismatches"
  fi

  assert_contains "identity_mismatch_cmdhash" "$REAPER_LAST_REASON" "reason should indicate command-hash mismatch"
}

test_reap_orphans_respects_kill_budget() {
  REAPER_DRY_RUN=0
  REAPER_ORPHAN_MIN_AGE_SEC=0
  REAPER_MAX_KILLS=1
  _kill_process() {
    REAPER_LAST_REASON="killed"
    return 0
  }

  local detections
  detections=$'10|opencode|100|999|children=0|Mon Mar 09 01:02:03 2026|hash10\n20|fzf|200|999||Mon Mar 09 01:02:03 2026|hash20'

  local out
  out="$(reap_orphans "$detections")"

  assert_contains "10|opencode|100|killed|killed" "$out" "first process should be killed under budget"
  assert_contains "20|fzf|200|skipped|budget_exceeded" "$out" "second process should be skipped when budget exceeded"
}

test_reap_orphans_failed_kill_does_not_consume_budget() {
  REAPER_DRY_RUN=0
  REAPER_ORPHAN_MIN_AGE_SEC=0
  REAPER_MAX_KILLS=1
  _kill_process() {
    if [ "$1" = "10" ]; then
      REAPER_LAST_REASON="term_failed"
      return 1
    fi
    REAPER_LAST_REASON="killed"
    return 0
  }

  local detections
  detections=$'10|opencode|100|999|children=0|Mon Mar 09 01:02:03 2026|hash10\n20|fzf|200|999||Mon Mar 09 01:02:03 2026|hash20'

  local out
  out="$(reap_orphans "$detections")"

  assert_contains "10|opencode|100|failed|term_failed" "$out" "failed kill should be recorded"
  assert_contains "20|fzf|200|killed|killed" "$out" "failed attempt must not consume kill budget"
}

test_validate_candidate_missing_comm_reason() {
  _get_ps_comm() { echo ""; }
  _get_ps_ppid() { echo "1"; }
  _get_elapsed_sec() { echo "999"; }
  _has_children() { return 1; }
  _get_ps_start_token() { echo "Mon Mar 09 01:02:03 2026"; }
  _get_ps_commandline() { echo "/opt/homebrew/bin/opencode --session alpha"; }
  _hash_text() { echo "hash-alpha"; }

  if _validate_candidate "10" "opencode" "0" "children=0" "Mon Mar 09 01:02:03 2026" "hash-alpha"; then
    fail "_validate_candidate should fail when comm is missing"
  fi

  assert_contains "missing" "$REAPER_LAST_REASON" "missing comm should set reason=missing"
}

test_validate_candidate_not_orphan_reason() {
  _get_ps_comm() { echo "opencode"; }
  _get_ps_ppid() { echo "123"; }
  _get_elapsed_sec() { echo "999"; }
  _has_children() { return 1; }
  _get_ps_start_token() { echo "Mon Mar 09 01:02:03 2026"; }
  _get_ps_commandline() { echo "/opt/homebrew/bin/opencode --session alpha"; }
  _hash_text() { echo "hash-alpha"; }

  if _validate_candidate "10" "opencode" "0" "children=0" "Mon Mar 09 01:02:03 2026" "hash-alpha"; then
    fail "_validate_candidate should fail when ppid is not 1"
  fi

  assert_contains "not_orphan" "$REAPER_LAST_REASON" "non-orphan ppid should set reason=not_orphan"
}

test_validate_candidate_too_young_reason() {
  _get_ps_comm() { echo "opencode"; }
  _get_ps_ppid() { echo "1"; }
  _get_elapsed_sec() { echo "0"; }
  _has_children() { return 1; }
  _get_ps_start_token() { echo "Mon Mar 09 01:02:03 2026"; }
  _get_ps_commandline() { echo "/opt/homebrew/bin/opencode --session alpha"; }
  _hash_text() { echo "hash-alpha"; }

  if _validate_candidate "10" "opencode" "1" "children=0" "Mon Mar 09 01:02:03 2026" "hash-alpha"; then
    fail "_validate_candidate should fail for too-young process"
  fi

  assert_contains "too_young" "$REAPER_LAST_REASON" "too-young process should set reason=too_young"
}

test_validate_candidate_missing_commandline_reason() {
  _get_ps_comm() { echo "opencode"; }
  _get_ps_ppid() { echo "1"; }
  _get_elapsed_sec() { echo "999"; }
  _has_children() { return 1; }
  _get_ps_start_token() { echo "Mon Mar 09 01:02:03 2026"; }
  _get_ps_commandline() { echo ""; }
  _hash_text() { echo "hash-alpha"; }

  if _validate_candidate "10" "opencode" "0" "children=0" "Mon Mar 09 01:02:03 2026" "hash-alpha"; then
    fail "_validate_candidate should fail when commandline is missing"
  fi

  assert_contains "missing_commandline" "$REAPER_LAST_REASON" "missing commandline should set reason=missing_commandline"
}

test_reap_orphans_dry_run
test_reap_orphans_status_mapping
test_validate_candidate_requires_start_token_match
test_validate_candidate_requires_command_hash_match
test_reap_orphans_respects_kill_budget
test_reap_orphans_failed_kill_does_not_consume_budget
test_validate_candidate_missing_comm_reason
test_validate_candidate_not_orphan_reason
test_validate_candidate_too_young_reason
test_validate_candidate_missing_commandline_reason

printf 'PASS: test_reaper.sh\n'
