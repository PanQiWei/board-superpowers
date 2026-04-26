#!/usr/bin/env bash
# tests/common-helpers.sh — assert scripts/lib/common.sh helper contracts
# per Card 1 Phase D Slice 4.
#
# Contracts under test:
#   bsp_normalize_repo_path <abs-repo-root> — strip leading "/", replace
#       remaining "/" with "-"; reject relative paths.
#   bsp_pick_worktree_dir [repo_root] — 3-priority resolution
#       (env > project-local .worktrees/ > default) per ADR-0003 and
#       docs/architecture/0005-contracts/07-path-conventions.md L51-58.
#   bsp_host_state_dir <repo_root> — emit
#       ${HOME}/.board-superpowers/repos/<normalized>
#       (signature change: was <host> <repo>).
#   bsp_audit_local_path <repo_root> — emit
#       ${HOME}/.board-superpowers/repos/<normalized>/audit-local.jsonl
#       (signature change: was <host> <repo>).
#
# Hermeticity policy: every scenario sources common.sh in a subshell with
# a controlled HOME so we never touch the real ~/.board-superpowers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMMON_SH="${PLUGIN_ROOT}/scripts/lib/common.sh"

if [ ! -f "${COMMON_SH}" ]; then
    printf 'FATAL: %s not found\n' "${COMMON_SH}" >&2
    exit 99
fi

PASS=0
FAIL=0

assert_eq() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    if [ "${actual}" = "${expected}" ]; then
        printf '  PASS — %s\n' "${label}"
        PASS=$((PASS + 1))
    else
        printf '  FAIL — %s\n    expected: %q\n    actual:   %q\n' \
            "${label}" "${expected}" "${actual}" >&2
        FAIL=$((FAIL + 1))
    fi
}

assert_nonzero() {
    local label="$1"
    local actual="$2"
    if [ "${actual}" != "0" ]; then
        printf '  PASS — %s (exit=%s)\n' "${label}" "${actual}"
        PASS=$((PASS + 1))
    else
        printf '  FAIL — %s: expected non-zero, got %s\n' "${label}" "${actual}" >&2
        FAIL=$((FAIL + 1))
    fi
}

# Run a one-liner sourcing common.sh and emitting a single line of stdout.
# Usage: call_helper "<bash code>"; prints stdout, captures status separately.
call_helper() {
    set +e
    bash -c "set -euo pipefail; source '${COMMON_SH}'; $1" 2>/dev/null
    local rc=$?
    set -e
    return ${rc}
}

# Capture both stdout and exit code from a helper invocation.
# Sets globals OUT and RC.
capture_helper() {
    local code="$1"
    set +e
    OUT="$(bash -c "set -euo pipefail; source '${COMMON_SH}'; ${code}" 2>/dev/null)"
    RC=$?
    set -e
}

# ---------------------------------------------------------------------------
# Scenario 1: bsp_normalize_repo_path — happy path
# ---------------------------------------------------------------------------
printf 'Scenario: bsp_normalize_repo_path happy paths\n'

capture_helper 'bsp_normalize_repo_path /Users/foo/bar-baz'
assert_eq 'normalize /Users/foo/bar-baz' 'Users-foo-bar-baz' "${OUT}"

capture_helper 'bsp_normalize_repo_path /a/b/c'
assert_eq 'normalize /a/b/c' 'a-b-c' "${OUT}"

capture_helper 'bsp_normalize_repo_path /Users/foo/bar/'
assert_eq 'normalize trailing slash /Users/foo/bar/' 'Users-foo-bar' "${OUT}"

capture_helper 'bsp_normalize_repo_path /Users/panqiwei/Dev/repos/nemori-ai/board-superpowers'
assert_eq 'normalize deep path' 'Users-panqiwei-Dev-repos-nemori-ai-board-superpowers' "${OUT}"

# ---------------------------------------------------------------------------
# Scenario 2: bsp_normalize_repo_path — relative path is a usage error
# ---------------------------------------------------------------------------
printf 'Scenario: bsp_normalize_repo_path rejects relative paths\n'

capture_helper 'bsp_normalize_repo_path relative/path'
assert_nonzero 'relative path → non-zero exit' "${RC}"

capture_helper 'bsp_normalize_repo_path foo'
assert_nonzero 'bare-word path → non-zero exit' "${RC}"

# ---------------------------------------------------------------------------
# Scenario 3: bsp_pick_worktree_dir — env override (priority 1)
# ---------------------------------------------------------------------------
printf 'Scenario: bsp_pick_worktree_dir env override\n'

capture_helper 'BOARD_SP_WORKTREE_DIR=/custom/wt bsp_pick_worktree_dir'
assert_eq 'env override (no repo arg)' '/custom/wt' "${OUT}"

# Even if a repo arg with a gitignored .worktrees/ is passed, env wins.
TMP="$(mktemp -d)"
(
    cd "${TMP}"
    git init -q -b main
    git config user.email test@example.com
    git config user.name 'Test'
    mkdir .worktrees
    printf '.worktrees/\n' > .gitignore
    git add .gitignore
    git -c commit.gpgsign=false commit -q -m gitignore
)
capture_helper "BOARD_SP_WORKTREE_DIR=/custom/wt bsp_pick_worktree_dir '${TMP}'"
assert_eq 'env override beats project-local .worktrees' '/custom/wt' "${OUT}"
rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 4: bsp_pick_worktree_dir — project-local .worktrees/ (priority 2)
# ---------------------------------------------------------------------------
printf 'Scenario: bsp_pick_worktree_dir project-local .worktrees/ lookup\n'

# Happy path: dir exists AND is gitignored → priority 2 fires.
TMP="$(mktemp -d)"
(
    cd "${TMP}"
    git init -q -b main
    git config user.email test@example.com
    git config user.name 'Test'
    mkdir .worktrees
    printf '.worktrees/\n' > .gitignore
    git add .gitignore
    git -c commit.gpgsign=false commit -q -m gitignore
)
capture_helper "unset BOARD_SP_WORKTREE_DIR; HOME=/test/home bsp_pick_worktree_dir '${TMP}'"
assert_eq 'project-local .worktrees (dir exists + gitignored)' "${TMP}/.worktrees" "${OUT}"
rm -rf "${TMP}"

# Negative: dir exists but NOT gitignored → priority 2 must NOT match,
# falls through to priority 3 default.
TMP="$(mktemp -d)"
(
    cd "${TMP}"
    git init -q -b main
    git config user.email test@example.com
    git config user.name 'Test'
    mkdir .worktrees
    # No .gitignore at all — .worktrees is tracked-eligible.
)
capture_helper "unset BOARD_SP_WORKTREE_DIR; HOME=/test/home bsp_pick_worktree_dir '${TMP}'"
assert_eq 'project-local .worktrees (dir exists but NOT gitignored) → default' \
    '/test/home/.config/superpowers/worktrees' "${OUT}"
rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 5: bsp_pick_worktree_dir — default (priority 3)
# ---------------------------------------------------------------------------
printf 'Scenario: bsp_pick_worktree_dir default fallback\n'

# Repo without any .worktrees dir → default.
TMP="$(mktemp -d)"
capture_helper "unset BOARD_SP_WORKTREE_DIR; HOME=/test/home bsp_pick_worktree_dir '${TMP}'"
assert_eq 'default (no env, no .worktrees dir)' '/test/home/.config/superpowers/worktrees' "${OUT}"
rm -rf "${TMP}"

# No repo_root arg at all → also default.
capture_helper 'unset BOARD_SP_WORKTREE_DIR; HOME=/test/home bsp_pick_worktree_dir'
assert_eq 'default (no args at all)' '/test/home/.config/superpowers/worktrees' "${OUT}"

# Path that is not a git repo (mkdir + .worktrees but no `git init`) →
# `git check-ignore` returns non-zero, falls through to default.
TMP="$(mktemp -d)"
mkdir -p "${TMP}/.worktrees"
capture_helper "unset BOARD_SP_WORKTREE_DIR; HOME=/test/home bsp_pick_worktree_dir '${TMP}'"
assert_eq 'default (.worktrees dir but not a git repo)' \
    '/test/home/.config/superpowers/worktrees' "${OUT}"
rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 6: bsp_host_state_dir new signature
# ---------------------------------------------------------------------------
printf 'Scenario: bsp_host_state_dir <repo_root>\n'

capture_helper 'HOME=/test/home bsp_host_state_dir /Users/foo/bar-baz'
assert_eq 'host_state_dir new layout' '/test/home/.board-superpowers/repos/Users-foo-bar-baz' "${OUT}"

capture_helper 'HOME=/test/home bsp_host_state_dir /Users/panqiwei/Dev/repos/nemori-ai/board-superpowers'
assert_eq 'host_state_dir deep path' '/test/home/.board-superpowers/repos/Users-panqiwei-Dev-repos-nemori-ai-board-superpowers' "${OUT}"

# ---------------------------------------------------------------------------
# Scenario 7: bsp_audit_local_path new signature
# ---------------------------------------------------------------------------
printf 'Scenario: bsp_audit_local_path <repo_root>\n'

capture_helper 'HOME=/test/home bsp_audit_local_path /Users/foo/bar-baz'
assert_eq 'audit_local_path new layout' '/test/home/.board-superpowers/repos/Users-foo-bar-baz/audit-local.jsonl' "${OUT}"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\nResults: %d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" = "0" ]
