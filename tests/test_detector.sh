#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local msg="$3"
  [ "$expected" = "$actual" ] || fail "$msg (expected=$expected actual=$actual)"
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

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

MOCK_BIN="$TMP_DIR/mockbin"
mkdir -p "$MOCK_BIN"

cat > "$MOCK_BIN/ps" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-p" ]]; then
  pid="${2:-}"
  var="MOCK_ETIME_${pid}"
  echo "${!var:-${MOCK_ETIME_DEFAULT:-00:00:00}}"
  exit 0
fi

if [[ "${1:-}" == "-eo" ]] && [[ "${2:-}" == "ppid,pid,rss,comm" ]]; then
  cat "${MOCK_PS_EO_FILE}"
  exit 0
fi

exit 1
EOF

cat > "$MOCK_BIN/pgrep" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-P" ]]; then
  pid="${2:-}"
  var="MOCK_CHILDREN_${pid}"
  value="${!var:-}"
  if [[ -n "$value" ]]; then
    for child in $value; do
      printf '%s\n' "$child"
    done
  fi
  exit 0
fi

exit 1
EOF

chmod +x "$MOCK_BIN/ps" "$MOCK_BIN/pgrep"
export PATH="$MOCK_BIN:$PATH"

source "$ROOT_DIR/conf/defaults.conf"
source "$ROOT_DIR/lib/detector.sh"

test_get_elapsed_sec_leading_zero() {
  export MOCK_ETIME_777="09:08"
  local got
  got="$(_get_elapsed_sec 777)"
  assert_eq "548" "$got" "_get_elapsed_sec should parse leading-zero values as base-10"
}

test_get_elapsed_sec_day_hour() {
  export MOCK_ETIME_778="1-02:03:04"
  local got
  got="$(_get_elapsed_sec 778)"
  assert_eq "93784" "$got" "_get_elapsed_sec should parse dd-hh:mm:ss format"
}

test_detect_orphans_filters() {
  export REAPER_ORPHAN_MIN_AGE_SEC=3600
  REAPER_TARGETS=("opencode:children=0" "opencode:children=0" "/bin/zsh:children=0" "fzf")

  export MOCK_PS_EO_FILE="$TMP_DIR/ps-eo.txt"
  cat > "$MOCK_PS_EO_FILE" <<'EOF'
1 101 70000 opencode
1 102 71000 opencode
1 150 72000 opencode-helper
1 201 384 /bin/zsh
1 202 384 /bin/zsh
1 301 960 fzf
2 401 10000 opencode
EOF

  export MOCK_ETIME_101="11-00:00:00"
  export MOCK_ETIME_102="00:30:00"
  export MOCK_ETIME_150="11-00:00:00"
  export MOCK_ETIME_201="11-00:00:00"
  export MOCK_ETIME_202="11-00:00:00"
  export MOCK_ETIME_301="11-00:00:00"
  export MOCK_ETIME_401="11-00:00:00"

  export MOCK_CHILDREN_201="900"

  local out
  out="$(detect_orphans)"

  local count
  count="$(printf '%s\n' "$out" | grep -c .)"

  assert_eq "3" "$count" "detect_orphans should return only eligible targets"
  assert_contains "101|opencode|70000|" "$out" "eligible orphan opencode should be detected"
  assert_contains "202|/bin/zsh|384|" "$out" "eligible orphan zsh should be detected"
  assert_contains "301|fzf|960|" "$out" "eligible orphan fzf should be detected"
  assert_contains "101|opencode|70000|950400|children=0" "$out" "condition should be included in detector output"
  assert_not_contains "102|opencode|" "$out" "young process should be excluded by min age"
  assert_not_contains "150|opencode-helper|" "$out" "partial command match should not be detected"
  assert_not_contains "201|/bin/zsh|" "$out" "child-bearing process should be excluded when children=0"
  assert_not_contains "401|opencode|" "$out" "non-orphan process should be excluded"
}

test_get_elapsed_sec_leading_zero
test_get_elapsed_sec_day_hour
test_detect_orphans_filters

printf 'PASS: test_detector.sh\n'
