#!/bin/zsh
# Smoke test against the real Finder sidebar of the current user.
# Adds a temporary folder, exercises every command, removes it, and confirms the list is back to how it was.
set -euo pipefail
BIN="${BIN:-./sidebarctl}"
fail() { echo "FAIL: $*" >&2; exit 1; }
expect_rc() { local want=$1; shift; set +e; "$@" >/dev/null 2>&1; local rc=$?; set -e; [[ $rc == $want ]] || fail "expected exit $want, got $rc: $*"; }

"$BIN" version >/dev/null
"$BIN" help >/dev/null

before=$("$BIN" list)
"$BIN" list --json | /usr/bin/python3 -c "import json,sys; json.load(sys.stdin)" || fail "list --json is not valid JSON"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/sidebarctl test é XXXXXX")   # space + unicode on purpose
trap '"$BIN" remove "$tmp" >/dev/null 2>&1 || true; rm -f "$tmp/file.txt"; rmdir "$tmp" 2>/dev/null || true' EXIT

expect_rc 1 "$BIN" contains "$tmp"
"$BIN" add "$tmp" --name "sidebarctl-test" >/dev/null
expect_rc 0 "$BIN" contains "$tmp"
expect_rc 0 "$BIN" contains "$tmp/"                                     # trailing slash
expect_rc 0 "$BIN" contains "file://${tmp// /%20}/"                     # file:// URL
[[ "$("$BIN" add "$tmp")" == already* ]] || fail "add is not idempotent"
"$BIN" remove "$tmp" >/dev/null
expect_rc 1 "$BIN" contains "$tmp"
expect_rc 1 "$BIN" remove "$tmp"

# input validation
expect_rc 2 "$BIN" add /definitely/not/here
touch "$tmp/file.txt"; expect_rc 2 "$BIN" add "$tmp/file.txt"           # not a folder
expect_rc 2 "$BIN" add ""
expect_rc 2 "$BIN" contains ""
expect_rc 2 "$BIN" add "$tmp" --name
expect_rc 2 "$BIN" add "$tmp" --name --top
expect_rc 2 "$BIN" add "$tmp" --bogus
expect_rc 2 "$BIN" list --bogus
expect_rc 2 "$BIN" version extra
expect_rc 2 "$BIN" nonsense

after=$("$BIN" list)
[[ "$before" == "$after" ]] || { diff <(echo "$before") <(echo "$after"); fail "sidebar differs after test"; }
echo "smoke test passed"
