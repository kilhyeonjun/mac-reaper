#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_file_contains() {
  local file="$1"
  local needle="$2"
  local msg="$3"
  grep -Fq "$needle" "$file" || fail "$msg"
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

TEST_HOME="$TMP_DIR/home"
MOCK_BIN="$TMP_DIR/mockbin"
MOCK_STATE="$TMP_DIR/launchctl-loaded"
mkdir -p "$TEST_HOME/Library/LaunchAgents" "$MOCK_BIN"

cat > "$MOCK_BIN/launchctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

state_file="${MOCK_STATE_FILE}"
cmd="${1:-}"

case "$cmd" in
  bootout)
    rm -f "$state_file"
    exit 0
    ;;
  bootstrap)
    touch "$state_file"
    exit 0
    ;;
  print)
    [ -f "$state_file" ]
    ;;
  list)
    [ -f "$state_file" ] && printf '123\t0\tnet.kilhyeonjun.mac-reaper\n'
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF

chmod +x "$MOCK_BIN/launchctl"

run_install() {
  env HOME="$TEST_HOME" PATH="$MOCK_BIN:$PATH" MOCK_STATE_FILE="$MOCK_STATE" "$ROOT_DIR/install.sh" >/tmp/mac-reaper-test-install.out
}

run_uninstall() {
  env HOME="$TEST_HOME" PATH="$MOCK_BIN:$PATH" MOCK_STATE_FILE="$MOCK_STATE" "$ROOT_DIR/uninstall.sh" >/tmp/mac-reaper-test-uninstall.out
}

test_install_is_idempotent_and_generates_expected_plist() {
  run_install
  run_install

  local plist
  plist="$TEST_HOME/Library/LaunchAgents/net.kilhyeonjun.mac-reaper.plist"
  [ -f "$plist" ] || fail "install should generate LaunchAgent plist"

  assert_file_contains "$plist" "<string>$ROOT_DIR/reap.sh</string>" "plist should contain resolved reap.sh path"
  assert_file_contains "$plist" "<string>$TEST_HOME</string>" "plist should contain resolved HOME"
  assert_file_contains "$plist" "<integer>10800</integer>" "plist should contain 3-hour interval"
  assert_file_contains "$plist" "<key>RunAtLoad</key>" "plist should run at load"
}

test_uninstall_is_idempotent() {
  run_uninstall
  run_uninstall

  local plist
  plist="$TEST_HOME/Library/LaunchAgents/net.kilhyeonjun.mac-reaper.plist"
  [ ! -f "$plist" ] || fail "uninstall should remove plist"
}

test_install_is_idempotent_and_generates_expected_plist
test_uninstall_is_idempotent

printf 'PASS: test_install_uninstall.sh\n'
