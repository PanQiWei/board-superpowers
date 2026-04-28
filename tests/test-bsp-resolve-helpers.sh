#!/usr/bin/env bash
# tests/test-bsp-resolve-helpers.sh
# Exit non-zero on any failure (set -e); print a one-line PASS/FAIL summary.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON="${REPO_ROOT}/scripts/lib/common.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

test_platform_cc() {
  result=$(env -i HOME="$HOME" PATH="$PATH" CLAUDE_SESSION_ID=cc_xyz \
    bash -c "source '$COMMON' && bsp_resolve_platform")
  [ "$result" = "claude-code" ] || fail "platform CC: got '$result'"
}

test_platform_codex() {
  result=$(env -i HOME="$HOME" PATH="$PATH" CODEX_THREAD_ID=t_xyz \
    bash -c "source '$COMMON' && bsp_resolve_platform")
  [ "$result" = "codex-cli" ] || fail "platform codex: got '$result'"
}

test_platform_unknown() {
  result=$(env -i HOME="$HOME" PATH="$PATH" \
    bash -c "source '$COMMON' && bsp_resolve_platform")
  [ "$result" = "unknown" ] || fail "platform unknown: got '$result'"
}

test_session_cc() {
  result=$(env -i HOME="$HOME" PATH="$PATH" PWD="$PWD" CLAUDE_SESSION_ID=cc_xyz \
    bash -c "source '$COMMON' && bsp_resolve_session_id")
  [ "$result" = "cc_xyz" ] || fail "session CC: got '$result'"
}

test_session_codex() {
  result=$(env -i HOME="$HOME" PATH="$PATH" PWD="$PWD" CODEX_THREAD_ID=t_xyz \
    bash -c "source '$COMMON' && bsp_resolve_session_id")
  [ "$result" = "t_xyz" ] || fail "session codex: got '$result'"
}

test_session_pwd_fallback() {
  expected="${PWD//\//-}"
  result=$(env -i HOME="$HOME" PATH="$PATH" PWD="$PWD" \
    bash -c "source '$COMMON' && bsp_resolve_session_id")
  [ "$result" = "$expected" ] \
    || fail "session pwd-fallback: got '$result', expected '$expected'"
}

test_render_block_cc() {
  expected_sid='cc_xyz'
  result=$(env -i HOME="$HOME" PATH="$PATH" PWD="$PWD" CLAUDE_SESSION_ID=cc_xyz \
    bash -c "source '$COMMON' && bsp_render_creator_trace_block")
  echo "$result" | grep -qx '<!-- board-superpowers:creator-trace -->' \
    || fail "render: missing open marker"
  echo "$result" | grep -qx '<!-- /board-superpowers:creator-trace -->' \
    || fail "render: missing close marker"
  echo "$result" | grep -qx '\*\*Created-by:\*\* claude-code' \
    || fail "render: wrong Created-by"
  echo "$result" | grep -qx "\\*\\*Session-id:\\*\\* ${expected_sid}" \
    || fail "render: wrong Session-id"
}

test_platform_cc
test_platform_codex
test_platform_unknown
test_session_cc
test_session_codex
test_session_pwd_fallback
test_render_block_cc
echo 'PASS: 7/7'
