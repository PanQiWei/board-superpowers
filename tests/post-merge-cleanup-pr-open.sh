#!/usr/bin/env bash
# tests/post-merge-cleanup-pr-open.sh — assert post-merge-cleanup.sh
# exits 2 and leaves the worktree intact when the PR state is OPEN.
#
# Fake gh PATH-shim returns an OPEN JSON payload.

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

# ---------------------------------------------------------------------------
# Set up git repo + claim worktree
# ---------------------------------------------------------------------------

git -C "${TMPREPO}" init -q
git -C "${TMPREPO}" config user.email test@example.com
git -C "${TMPREPO}" config user.name Test
printf 'init\n' > "${TMPREPO}/README.md"
git -C "${TMPREPO}" add README.md
git -C "${TMPREPO}" -c commit.gpgsign=false commit -q -m init

git -C "${TMPREPO}" checkout -q -b "claim/99-some-title"
git -C "${TMPREPO}" checkout -q main

REPO_NAME="$(basename "${TMPREPO}")"
WT_BASE="${TMPHOME}/.config/superpowers/worktrees"
WT_PATH="${WT_BASE}/${REPO_NAME}/claim/99-some-title"

mkdir -p "$(dirname "${WT_PATH}")"
git -C "${TMPREPO}" worktree add "${WT_PATH}" "claim/99-some-title" -q

# ---------------------------------------------------------------------------
# Build fake gh shim returning OPEN
# ---------------------------------------------------------------------------

cat > "${TMPBIN}/gh" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
    pr)
        shift
        case "${1:-}" in
            list)
                printf '{"number":55,"state":"OPEN","mergedAt":null,"headRefName":"claim/99-some-title"}\n'
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

printf '\nRunning post-merge-cleanup.sh with OPEN PR ...\n'

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

check "exit code 2 (PR still OPEN)" test "${RC}" -eq 2

# Worktree must be intact.
check "worktree still present (not prematurely removed)" test -d "${WT_PATH}"

# Branch must be intact.
check "branch still present" \
    bash -c "git -C '${TMPREPO}' branch --list 'claim/99-some-title' | grep -q ."

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\nResults: %d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
