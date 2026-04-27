#!/usr/bin/env bash
# tests/post-merge-cleanup-pr-merged.sh — assert post-merge-cleanup.sh
# correctly removes the worktree, deletes the branch, and writes an
# audit row when the PR state is MERGED.
#
# Fake gh PATH-shim: responds to `gh pr list ... --jq .[0]` with a
# pre-canned MERGED JSON payload.
#
# Hermeticity: uses a tmp git repo + tmp HOME; never touches real state.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPT_UNDER_TEST="${PLUGIN_ROOT}/scripts/post-merge-cleanup.sh"

if [ ! -f "${SCRIPT_UNDER_TEST}" ]; then
    printf 'FATAL: %s not found\n' "${SCRIPT_UNDER_TEST}" >&2
    exit 99
fi

TMPREPO="$(mktemp -d)"
TMPHOME="$(mktemp -d)"
TMPBIN="$(mktemp -d)"
trap 'rm -rf "${TMPREPO}" "${TMPHOME}" "${TMPBIN}"' EXIT

PASS=0
FAIL=0

check() {
    local label="$1"
    shift
    if "$@"; then
        printf '  PASS — %s\n' "${label}"
        PASS=$((PASS + 1))
    else
        printf '  FAIL — %s\n' "${label}" >&2
        FAIL=$((FAIL + 1))
    fi
}

check_not() {
    local label="$1"
    shift
    if "$@"; then
        printf '  FAIL — %s\n' "${label}" >&2
        FAIL=$((FAIL + 1))
    else
        printf '  PASS — %s\n' "${label}"
        PASS=$((PASS + 1))
    fi
}

# ---------------------------------------------------------------------------
# Set up a bare git repo + claim worktree
# ---------------------------------------------------------------------------

# Init primary repo.
git -C "${TMPREPO}" init -q
git -C "${TMPREPO}" config user.email test@example.com
git -C "${TMPREPO}" config user.name Test
# Need at least one commit to create branches.
printf 'init\n' > "${TMPREPO}/README.md"
git -C "${TMPREPO}" add README.md
git -C "${TMPREPO}" -c commit.gpgsign=false commit -q -m init

# Create the claim branch, then switch back to main so the worktree add works.
git -C "${TMPREPO}" checkout -q -b "claim/99-some-title"
git -C "${TMPREPO}" checkout -q main

# Determine the worktree base path.
REPO_NAME="$(basename "${TMPREPO}")"
WT_BASE="${TMPHOME}/.config/superpowers/worktrees"
WT_PATH="${WT_BASE}/${REPO_NAME}/claim/99-some-title"

mkdir -p "$(dirname "${WT_PATH}")"
git -C "${TMPREPO}" worktree add "${WT_PATH}" "claim/99-some-title" -q

# Verify setup.
check "worktree exists before cleanup" test -d "${WT_PATH}"
check "branch exists before cleanup" \
    bash -c "git -C '${TMPREPO}' branch --list 'claim/99-some-title' | grep -q ."

# ---------------------------------------------------------------------------
# Build fake gh shim
# ---------------------------------------------------------------------------

# The fake gh must handle:
#   gh pr list --repo <owner>/<repo> --head claim/99-some-title --state all
#              --json number,state,mergedAt,headRefName --jq .[0]
# → returns MERGED JSON.

cat > "${TMPBIN}/gh" <<'STUB'
#!/usr/bin/env bash
# Fake gh stub for post-merge-cleanup tests.
case "${1:-}" in
    pr)
        shift
        case "${1:-}" in
            list)
                # Return a MERGED PR payload.
                printf '{"number":42,"state":"MERGED","mergedAt":"2026-04-27T10:00:00Z","headRefName":"claim/99-some-title"}\n'
                exit 0
                ;;
        esac
        ;;
esac
printf 'fake gh: unhandled command %s\n' "$*" >&2
exit 1
STUB
chmod +x "${TMPBIN}/gh"

# ---------------------------------------------------------------------------
# Run the cleanup script
# ---------------------------------------------------------------------------

printf '\nRunning post-merge-cleanup.sh --card 99 --owner test ...\n'

set +e
HOME="${TMPHOME}" BOARD_SP_WORKTREE_DIR="${WT_BASE}" \
    PATH="${TMPBIN}:${PLUGIN_ROOT}/scripts:/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin" \
    CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}" \
    bash "${SCRIPT_UNDER_TEST}" \
        --card 99 \
        --owner test \
        --repo-root "${TMPREPO}" \
    2>/dev/null
RC=$?
set -e

check "exit code 0 (MERGED cleanup done)" test "${RC}" -eq 0

# ---------------------------------------------------------------------------
# Assert: worktree removed
# ---------------------------------------------------------------------------

check_not "worktree removed" test -d "${WT_PATH}"

# ---------------------------------------------------------------------------
# Assert: branch deleted
# ---------------------------------------------------------------------------

check_not "branch deleted" \
    bash -c "git -C '${TMPREPO}' branch --list 'claim/99-some-title' | grep -q ."

# ---------------------------------------------------------------------------
# Assert: audit row written (action_id 113, jsonl)
# ---------------------------------------------------------------------------

NORMALIZED="$(printf '%s' "${TMPREPO}" | sed 's|^/||; s|/|-|g')"
AUDIT_FILE="${TMPHOME}/.board-superpowers/repos/${NORMALIZED}/audit-local.jsonl"

check "audit file exists" test -f "${AUDIT_FILE}"

if [ -f "${AUDIT_FILE}" ]; then
    AUDIT_LINE="$(tail -1 "${AUDIT_FILE}")"

    check "audit row has action_id 113" \
        bash -c "printf '%s' '${AUDIT_LINE}' | python3 -c \"
import json, sys
d = json.loads(sys.stdin.read())
assert d['action_id'] == '113', f'expected 113 got {d[\\\"action_id\\\"]}'
\""

    check "audit row has decision_class A" \
        bash -c "printf '%s' '${AUDIT_LINE}' | python3 -c \"
import json, sys
d = json.loads(sys.stdin.read())
assert d['decision_class'] == 'A', f'expected A got {d[\\\"decision_class\\\"]}'
\""

    check "audit row has skill consuming-card" \
        bash -c "printf '%s' '${AUDIT_LINE}' | python3 -c \"
import json, sys
d = json.loads(sys.stdin.read())
assert d['skill'] == 'consuming-card', f'unexpected skill {d[\\\"skill\\\"]}'
\""
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\nResults: %d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
