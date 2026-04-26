#!/usr/bin/env bash
# scripts/check-deps.sh — verify required CLI dependencies + routing block
# for board-superpowers.
#
# Called by:
#   - hooks/session-start.sh (every session, fast-path verification)
#   - using-board-superpowers SKILL.md (fallback when hook output is missing)
#
# Exit codes (per docs/architecture/0002-product-features-and-flows/05-bootstrap-surface.md
# § "Layer 1 dep check (§1.5.0)" and 0005-contracts/02-hook-contracts.md):
#   0 — all dependencies present + routing block present
#       (or no AGENTS.md / CLAUDE.md exists, in which case the routing
#       check is skipped — the asymmetric "no file is fine, file without
#       marker is not" rule keeps the dep check silent in repos that
#       don't use these files at all)
#   2 — required binary is NOT installed, OR AGENTS.md / CLAUDE.md
#       exists but lacks the "## board-superpowers session routing"
#       heading
#   3 — required binary IS installed but a runtime invariant fails
#       (e.g., `gh` exists but lacks the `project` / `read:project`
#       scope, or `gh` is not authenticated)
#
# Stdout: human-readable status banner suitable for hookSpecificOutput.additionalContext
#
# Layer-classification rationale: a missing binary is a static
# "install something" problem (exit 2 = caller can prompt the user to
# install the dep). A binary present but unauthenticated/under-scoped is
# a runtime invariant problem (exit 3 = caller can prompt the user to
# re-authenticate). Card 2's hook uses these distinct codes to choose
# between two different INVOKE markers; Card 1 establishes the contract.

set -euo pipefail

# Resolve our own location and source common helpers.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

# --- Failure tracking ---------------------------------------------------
# Three independent counters — order of priority for exit-code resolution:
#   MISSING_DEPS or MISSING_ROUTING -> exit 2
#   else RUNTIME_FAILURES           -> exit 3
#   else                            -> exit 0

declare -i MISSING_DEPS=0
declare -i MISSING_ROUTING=0
declare -i RUNTIME_FAILURES=0

check_cmd() {
    local cmd="${1:?}"
    local hint="${2:-}"
    if command -v "${cmd}" >/dev/null 2>&1; then
        printf '  ✓ %s\n' "${cmd}"
    else
        printf '  ✗ %s — MISSING (%s)\n' "${cmd}" "${hint}"
        MISSING_DEPS=$((MISSING_DEPS + 1))
    fi
}

check_gh_scope() {
    if ! command -v gh >/dev/null 2>&1; then
        return  # Already counted by check_cmd above as a missing dep.
    fi
    # gh auth status emits scopes on stderr; grep them.
    if gh auth status 2>&1 | grep -qE "'(read:project|project)'"; then
        printf '  ✓ gh auth has project scope\n'
    else
        printf '  ✗ gh auth missing project scope — run: gh auth refresh -s project,read:project\n'
        RUNTIME_FAILURES=$((RUNTIME_FAILURES + 1))
    fi
}

check_routing_block() {
    # Resolve the git toplevel for the cwd. If we're not inside a git
    # repo, the routing-block check is meaningless — skip silently.
    local toplevel
    if ! toplevel="$(git rev-parse --show-toplevel 2>/dev/null)"; then
        return
    fi

    # Asymmetric rule (per 05-bootstrap-surface.md):
    #   - no AGENTS.md AND no CLAUDE.md → skipped (silent, exit 0 path)
    #   - either file present without the heading → exit 2
    # Detection is heading-presence only. Card 2 will tighten this to a
    # SHA-hash protocol; for v0.1.1 a literal heading match suffices.
    local agents="${toplevel}/AGENTS.md"
    local claude="${toplevel}/CLAUDE.md"
    local heading='## board-superpowers session routing'
    local saw_file=0
    local saw_marker=0

    if [ -f "${agents}" ]; then
        saw_file=1
        if grep -qF "${heading}" "${agents}"; then
            saw_marker=1
        fi
    fi
    if [ -f "${claude}" ]; then
        saw_file=1
        if grep -qF "${heading}" "${claude}"; then
            saw_marker=1
        fi
    fi

    if [ "${saw_file}" -eq 0 ]; then
        # Neither file exists — silent skip per spec.
        return
    fi

    if [ "${saw_marker}" -eq 1 ]; then
        printf '  ✓ board-superpowers routing block present\n'
    else
        printf '  ✗ AGENTS.md / CLAUDE.md present but routing block missing\n'
        MISSING_ROUTING=$((MISSING_ROUTING + 1))
    fi
}

printf 'board-superpowers dependency check:\n'
check_cmd gh "install via 'brew install gh'"
check_cmd python3 "macOS / Linux ship python3 by default"
check_cmd git "macOS ships git via Xcode CLT"
check_gh_scope
check_routing_block

# --- Exit-code resolution ----------------------------------------------
# Priority: install-time failures (deps / routing block) outrank runtime
# failures (auth / scope), because a fix-it prompt that says "install
# the binary" is meaningless if the binary is already installed.

if [ "${MISSING_DEPS}" -gt 0 ] || [ "${MISSING_ROUTING}" -gt 0 ]; then
    printf '\nDependency check failed: %d missing dep(s), %d missing routing block(s).\n' \
        "${MISSING_DEPS}" "${MISSING_ROUTING}" >&2
    exit 2
fi

if [ "${RUNTIME_FAILURES}" -gt 0 ]; then
    printf '\nRuntime check failed: %d runtime invariant(s) unsatisfied.\n' \
        "${RUNTIME_FAILURES}" >&2
    exit 3
fi

printf '\nAll dependencies satisfied (board-superpowers v0.1.0-minimum).\n'
exit 0
