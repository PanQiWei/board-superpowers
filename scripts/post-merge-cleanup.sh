#!/usr/bin/env bash
# scripts/post-merge-cleanup.sh — post-merge worktree + branch cleanup
# for a board-superpowers claim card (action_id 113, A-class).
#
# Called by consuming-card skill (Step 12) and optionally by the
# install-post-merge-cron.sh scheduler once the PR merges.
#
# Behavior (four steps when PR is MERGED):
#   1. Verify that a claim/<N>-* worktree exists under
#      $BOARD_SP_WORKTREE_DIR/<repo>/ (or default worktree base).
#      If absent, print "already cleaned up" and exit 0 (idempotent).
#   2. Query gh pr list for the claim branch; determine PR state.
#   3. Branch on PR state:
#        MERGED  → run cleanup (steps 4-5).
#        OPEN    → print "PR #X still OPEN" + exit 2 (retry later).
#        CLOSED  → print "PR #X closed without merge (action_id 103)" + exit 3.
#   4. Remove worktree via `git worktree remove`.
#      If worktree has uncommitted changes, refuse + exit 4.
#   5. Delete local claim branch (`git branch -D`).
#      If already gone, continue.
#   6. Append A-class audit row (action_id 113) via bsp_audit_local_write
#      (or scripts/audit-log-write.sh when available).
#
# Exit codes:
#   0 — cleanup done (or was already done / idempotent)
#   1 — bad args / fatal error (missing PR, git failure)
#   2 — PR still OPEN; caller should retry
#   3 — PR CLOSED without merge (failure path; different audit row)
#   4 — worktree has uncommitted changes; architect must intervene
#
# Safety: never `rm -rf`. Uses only `git worktree remove` + `git branch -D`.
#
# Args:
#   --card <N>           required  card number (issue number)
#   --owner <owner>      required  GitHub org / user (for gh pr list --json)
#   --repo-root <path>   optional  repo root (defaults: bsp_primary_repo_root PWD)

set -euo pipefail

# Re-derive PATH defensively so this script can be called from cron with
# a stripped PATH. Caller PATH is prepended so test PATH-shims take
# precedence; system dirs follow as a safe fallback.
PATH="${PATH:+${PATH}:}/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
# shellcheck source-path=SCRIPTDIR
. "${SCRIPT_DIR}/lib/common.sh"

# --- Argument parsing -------------------------------------------------------

CARD=""
OWNER=""
REPO_ROOT_ARG=""

while [ $# -gt 0 ]; do
    case "$1" in
        --card)      CARD="$2";      shift 2 ;;
        --owner)     OWNER="$2";     shift 2 ;;
        --repo-root) REPO_ROOT_ARG="$2"; shift 2 ;;
        *) bsp_die "unknown argument: $1" ;;
    esac
done

[ -n "${CARD}" ]  || bsp_die "missing required --card <N>"
[ -n "${OWNER}" ] || bsp_die "missing required --owner <github-owner>"

bsp_require_cmd git
bsp_require_cmd gh

# --- Resolve repo root ------------------------------------------------------

if [ -n "${REPO_ROOT_ARG}" ]; then
    REPO_ROOT="${REPO_ROOT_ARG}"
else
    REPO_ROOT="$(bsp_primary_repo_root "${PWD}" 2>/dev/null)" \
        || bsp_die "cannot resolve repo root from PWD; pass --repo-root explicitly"
fi

[ -d "${REPO_ROOT}" ] || bsp_die "repo root not a directory: ${REPO_ROOT}"

REPO_NAME="$(basename "${REPO_ROOT}")"

# --- Step 1: find the claim worktree ----------------------------------------

WORKTREE_BASE="$(bsp_pick_worktree_dir "${REPO_ROOT}")"
WORKTREE_SEARCH_ROOT="${WORKTREE_BASE}/${REPO_NAME}"

# Find a worktree directory whose last path component matches claim/<N>-*
# We need to find the worktree path: $WORKTREE_SEARCH_ROOT/claim/<N>-<slug>
WORKTREE_PATH=""
BRANCH_NAME=""

# Look for directories matching the pattern claim/<CARD>-* under the
# per-repo worktree search root. Use a glob without extglob.
if [ -d "${WORKTREE_SEARCH_ROOT}" ]; then
    for candidate in "${WORKTREE_SEARCH_ROOT}/claim/${CARD}"-*/; do
        # Strip trailing slash from glob result
        candidate="${candidate%/}"
        [ -d "${candidate}" ] || continue
        WORKTREE_PATH="${candidate}"
        BRANCH_NAME="claim/$(basename "${candidate}")"
        break
    done
fi

if [ -z "${WORKTREE_PATH}" ]; then
    bsp_log "no claim worktree for card #${CARD} — already cleaned up (idempotent)"
    exit 0
fi

bsp_log "found worktree: ${WORKTREE_PATH}"
bsp_log "branch: ${BRANCH_NAME}"

# --- Step 2: query PR state -------------------------------------------------

bsp_log "querying PR state for branch ${BRANCH_NAME} ..."

# gh pr list returns empty array when no PR matches; .[0] returns null.
PR_JSON=""
set +e
PR_JSON="$(gh pr list \
    --repo "${OWNER}/${REPO_NAME}" \
    --head "${BRANCH_NAME}" \
    --state all \
    --json number,state,mergedAt,headRefName \
    --jq '.[0]' 2>/dev/null)"
GH_RC=$?
set -e

if [ "${GH_RC}" -ne 0 ] || [ -z "${PR_JSON}" ] || [ "${PR_JSON}" = "null" ]; then
    bsp_die "no PR found for card #${CARD} (branch ${BRANCH_NAME})"
fi

# Parse state, number, mergedAt from JSON using python3.
PR_STATE="$(printf '%s\n' "${PR_JSON}" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d.get('state', ''))
")"

PR_NUMBER="$(printf '%s\n' "${PR_JSON}" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d.get('number', ''))
")"

PR_MERGED_AT="$(printf '%s\n' "${PR_JSON}" | python3 -c "
import json, sys
d = json.load(sys.stdin)
v = d.get('mergedAt') or ''
print(v)
")"

bsp_log "PR #${PR_NUMBER} state=${PR_STATE}"

# --- Step 3: branch on PR state ---------------------------------------------

case "${PR_STATE}" in
    MERGED)
        bsp_log "PR #${PR_NUMBER} is MERGED — proceeding with cleanup"
        ;;
    OPEN)
        bsp_log "PR #${PR_NUMBER} still OPEN — cleanup deferred"
        exit 2
        ;;
    CLOSED)
        bsp_log "PR #${PR_NUMBER} closed without merge — failure path; this is action_id 103, not 113"
        exit 3
        ;;
    *)
        bsp_die "unexpected PR state '${PR_STATE}' for PR #${PR_NUMBER}"
        ;;
esac

# --- Step 4: remove worktree ------------------------------------------------

bsp_log "removing worktree at ${WORKTREE_PATH} ..."

# Check for uncommitted changes in the worktree before removing.
# `git -C <path> status --porcelain` emits non-empty output when dirty.
# Also run git status directly inside the worktree as a belt-and-suspenders
# check. If the path is no longer a valid worktree, git status may fail —
# treat that as "not dirty" so we proceed with the remove.
PORCELAIN_OUT=""
set +e
PORCELAIN_OUT="$(git -C "${WORKTREE_PATH}" status --porcelain 2>/dev/null || true)"
set -e

if [ -n "${PORCELAIN_OUT}" ]; then
    bsp_warn "worktree ${WORKTREE_PATH} has uncommitted changes — architect must resolve before cleanup"
    bsp_warn "uncommitted files:"
    printf '%s\n' "${PORCELAIN_OUT}" >&2
    exit 4
fi

# Remove the worktree via git.
if git -C "${REPO_ROOT}" worktree remove "${WORKTREE_PATH}" 2>/dev/null; then
    bsp_log "worktree removed: ${WORKTREE_PATH}"
    WORKTREE_REMOVED=true
else
    # Worktree may have already been removed (concurrent call or manual cleanup).
    if [ ! -d "${WORKTREE_PATH}" ]; then
        bsp_log "worktree already gone: ${WORKTREE_PATH}"
        WORKTREE_REMOVED=true
    else
        bsp_die "git worktree remove failed for ${WORKTREE_PATH}"
    fi
fi

# --- Step 5: delete local claim branch --------------------------------------

bsp_log "deleting local branch ${BRANCH_NAME} ..."

BRANCH_DELETED=false
if git -C "${REPO_ROOT}" branch --list "${BRANCH_NAME}" | grep -q .; then
    if git -C "${REPO_ROOT}" branch -D "${BRANCH_NAME}" 2>/dev/null; then
        BRANCH_DELETED=true
    else
        bsp_warn "git branch -D ${BRANCH_NAME} failed — branch may already be gone"
    fi
else
    bsp_log "branch ${BRANCH_NAME} already gone (deleted by GitHub or prior cleanup)"
    BRANCH_DELETED=true
fi

# --- Step 6: write A-class audit row (action_id 113) -----------------------

bsp_log "writing audit row (action_id 113) ..."

AUDIT_SUMMARY="post-merge cleanup: card #${CARD} PR #${PR_NUMBER} merged at ${PR_MERGED_AT}; worktree_removed=${WORKTREE_REMOVED} branch_deleted=${BRANCH_DELETED}"

# Try audit-log-write.sh (full BYO-RDBMS path) first; fall back to
# bsp_audit_local_write (v1-minimum jsonl degraded mode).
AUDIT_SCRIPT="${SCRIPT_DIR}/audit-log-write.sh"
if [ -x "${AUDIT_SCRIPT}" ]; then
    set +e
    bash "${AUDIT_SCRIPT}" \
        --repo-root "${REPO_ROOT}" \
        --action-id "113" \
        --class "A" \
        --skill "consuming-card" \
        --summary "${AUDIT_SUMMARY}" \
        --payload "{\"card_number\":${CARD},\"pr_number\":${PR_NUMBER},\"merged_at\":\"${PR_MERGED_AT}\",\"worktree_removed\":${WORKTREE_REMOVED},\"branch_deleted\":${BRANCH_DELETED}}" \
        2>/dev/null
    AUDIT_RC=$?
    set -e
    if [ "${AUDIT_RC}" -ne 0 ]; then
        bsp_warn "audit-log-write.sh exited ${AUDIT_RC}; falling back to local jsonl"
        bsp_audit_local_write \
            "${REPO_ROOT}" "113" "A" "consuming-card" "${AUDIT_SUMMARY}"
    fi
else
    bsp_audit_local_write \
        "${REPO_ROOT}" "113" "A" "consuming-card" "${AUDIT_SUMMARY}"
fi

bsp_log "post-merge cleanup complete for card #${CARD} (PR #${PR_NUMBER})"
exit 0
