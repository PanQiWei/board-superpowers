#!/usr/bin/env bash
# scripts/check-deps.sh — verify required CLI dependencies for board-superpowers.
#
# Called by:
#   - hooks/session-start.sh (every session, fast-path verification)
#   - using-board-superpowers SKILL.md (fallback when hook output is missing)
#
# Exit codes:
#   0 — all dependencies present at acceptable versions
#   1 — at least one dependency missing or below minimum version
#
# Stdout: human-readable status banner suitable for hookSpecificOutput.additionalContext

set -euo pipefail

# Resolve our own location and source common helpers.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

declare -i FAILED=0

check_cmd() {
    local cmd="${1:?}"
    local hint="${2:-}"
    if command -v "${cmd}" >/dev/null 2>&1; then
        printf '  ✓ %s\n' "${cmd}"
    else
        printf '  ✗ %s — MISSING (%s)\n' "${cmd}" "${hint}"
        FAILED=$((FAILED + 1))
    fi
}

check_gh_scope() {
    if ! command -v gh >/dev/null 2>&1; then
        return  # Already counted by check_cmd above.
    fi
    # gh auth status emits scopes on stderr; grep them.
    if gh auth status 2>&1 | grep -qE "'(read:project|project)'"; then
        printf '  ✓ gh auth has project scope\n'
    else
        printf '  ✗ gh auth missing project scope — run: gh auth refresh -s project,read:project\n'
        FAILED=$((FAILED + 1))
    fi
}

printf 'board-superpowers dependency check:\n'
check_cmd gh "install via 'brew install gh'"
check_cmd python3 "macOS / Linux ship python3 by default"
check_cmd git "macOS ships git via Xcode CLT"
check_gh_scope

if [ "${FAILED}" -gt 0 ]; then
    printf '\n%d dependency check(s) failed. Fix before using board-superpowers.\n' "${FAILED}" >&2
    exit 1
fi

printf '\nAll dependencies satisfied (board-superpowers v0.1.0-minimum).\n'
exit 0
