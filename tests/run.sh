#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

"$ROOT_DIR/tests/test_detector.sh"
"$ROOT_DIR/tests/test_reaper.sh"
"$ROOT_DIR/tests/test_lock.sh"

printf 'PASS: all tests\n'
