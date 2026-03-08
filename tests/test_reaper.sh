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
  detections=$'10|opencode|100|999|children=0|Mon Mar 09 01:02:03 2026\n20|fzf|200|999||Mon Mar 09 01:02:03 2026'

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
  detections=$'10|opencode|100|999|children=0|Mon Mar 09 01:02:03 2026\n20|fzf|200|999||Mon Mar 09 01:02:03 2026'

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

  if _validate_candidate "10" "opencode" "0" "children=0" "Mon Mar 09 11:22:33 2026"; then
    fail "_validate_candidate should fail when start token mismatches"
  fi

  assert_contains "identity_mismatch_start" "$REAPER_LAST_REASON" "reason should indicate start-token mismatch"
}

test_reap_orphans_dry_run
test_reap_orphans_status_mapping
test_validate_candidate_requires_start_token_match

printf 'PASS: test_reaper.sh\n'
