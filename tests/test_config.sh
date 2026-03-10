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
grep -Fq "run_status=invalid_config" "$LOG_FILE" || fail "invalid config should emit run_status=invalid_config"
grep -Fq "failure_reason=invalid_config" "$LOG_FILE" || fail "invalid config should emit failure_reason=invalid_config"

set +e
REAPER_LOG_DIR="$LOG_DIR" REAPER_DRY_RUN=1 REAPER_MAX_KILLS="xyz" "$ROOT_DIR/reap.sh" >/tmp/mac-reaper-test-config2.out 2>/tmp/mac-reaper-test-config2.err
status2=$?
set -e

[ "$status2" -ne 0 ] || fail "invalid REAPER_MAX_KILLS should fail fast with non-zero exit"

grep -Fq "Invalid config" "$LOG_FILE" || fail "invalid max-kills config should be logged"

set +e
REAPER_LOG_DIR="$LOG_DIR" REAPER_DRY_RUN=1 REAPER_SIGNAL_GRACE="BAD" "$ROOT_DIR/reap.sh" >/tmp/mac-reaper-test-config3.out 2>/tmp/mac-reaper-test-config3.err
status3=$?
set -e

[ "$status3" -ne 0 ] || fail "invalid REAPER_SIGNAL_GRACE should fail fast"
grep -Fq "Invalid config" "$LOG_FILE" || fail "invalid grace signal should be logged"

set +e
REAPER_LOG_DIR="$LOG_DIR" REAPER_DRY_RUN=1 REAPER_SIGNAL_FORCE="BOGUS" "$ROOT_DIR/reap.sh" >/tmp/mac-reaper-test-config4.out 2>/tmp/mac-reaper-test-config4.err
status4=$?
set -e

[ "$status4" -ne 0 ] || fail "invalid REAPER_SIGNAL_FORCE should fail fast"
grep -Fq "Invalid config" "$LOG_FILE" || fail "invalid force signal should be logged"

set +e
REAPER_LOG_DIR="$LOG_DIR" REAPER_DRY_RUN=1 REAPER_ORPHAN_MIN_AGE_SEC="-1" "$ROOT_DIR/reap.sh" >/tmp/mac-reaper-test-config5.out 2>/tmp/mac-reaper-test-config5.err
status5=$?
set -e

[ "$status5" -ne 0 ] || fail "negative REAPER_ORPHAN_MIN_AGE_SEC should fail fast"
grep -Fq "Invalid config" "$LOG_FILE" || fail "invalid orphan age should be logged"

set +e
REAPER_LOG_DIR="$LOG_DIR" REAPER_DRY_RUN=1 REAPER_RETRY_ON_LOCK_SKIP="maybe" "$ROOT_DIR/reap.sh" >/tmp/mac-reaper-test-config6.out 2>/tmp/mac-reaper-test-config6.err
status6=$?
set -e

[ "$status6" -ne 0 ] || fail "invalid REAPER_RETRY_ON_LOCK_SKIP should fail fast"
grep -Fq "Invalid config" "$LOG_FILE" || fail "invalid retry toggle should be logged"

set +e
REAPER_LOG_DIR="$LOG_DIR" REAPER_DRY_RUN=1 REAPER_RETRY_LOCK_MAX_ATTEMPTS="abc" "$ROOT_DIR/reap.sh" >/tmp/mac-reaper-test-config7.out 2>/tmp/mac-reaper-test-config7.err
status7=$?
set -e

[ "$status7" -ne 0 ] || fail "invalid REAPER_RETRY_LOCK_MAX_ATTEMPTS should fail fast"
grep -Fq "Invalid config" "$LOG_FILE" || fail "invalid retry max attempts should be logged"

set +e
REAPER_LOG_DIR="$LOG_DIR" REAPER_DRY_RUN=1 REAPER_RETRY_LOCK_BACKOFF_SEC="-1" "$ROOT_DIR/reap.sh" >/tmp/mac-reaper-test-config8.out 2>/tmp/mac-reaper-test-config8.err
status8=$?
set -e

[ "$status8" -ne 0 ] || fail "negative REAPER_RETRY_LOCK_BACKOFF_SEC should fail fast"
grep -Fq "Invalid config" "$LOG_FILE" || fail "invalid retry backoff should be logged"

printf 'PASS: test_config.sh\n'
