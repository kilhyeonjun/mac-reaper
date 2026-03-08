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

source "$ROOT_DIR/lib/reaper.sh"

test_reap_orphans_dry_run() {
  REAPER_DRY_RUN=1
  local detections
  detections=$'10|opencode|100|999\n20|fzf|200|999'

  local out
  out="$(reap_orphans "$detections")"

  assert_contains "10|opencode|100|dry-run|would_kill" "$out" "dry-run should mark first process"
  assert_contains "20|fzf|200|dry-run|would_kill" "$out" "dry-run should mark second process"
}

test_reap_orphans_status_mapping() {
  REAPER_DRY_RUN=0
  _kill_process() {
    if [ "$1" = "10" ]; then
      REAPER_LAST_REASON="killed"
      return 0
    fi
    REAPER_LAST_REASON="identity_mismatch"
    return 1
  }

  local detections
  detections=$'10|opencode|100|999\n20|fzf|200|999'

  local out
  out="$(reap_orphans "$detections")"

  assert_contains "10|opencode|100|killed|killed" "$out" "successful kill should be marked killed with reason"
  assert_contains "20|fzf|200|failed|identity_mismatch" "$out" "failed kill should include reason"
}

test_reap_orphans_dry_run
test_reap_orphans_status_mapping

printf 'PASS: test_reaper.sh\n'
