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

test_platform_cc
test_platform_codex
test_platform_unknown
echo 'PASS: bsp_resolve_platform 3/3'
