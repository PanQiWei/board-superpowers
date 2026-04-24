#!/usr/bin/env bash
# board-superpowers / claim-card.sh
#
# Atomically claim a GitHub Project card for this Consumer session.
#
# Mechanism: distributed lock via `git push` on a namespaced claim branch.
# Creating a remote branch is atomic in git — if two sessions race to push
# the same new branch, exactly one wins. The winner holds the claim; the
# loser exits cleanly.
#
# The claim branch is ALSO the feature branch. No separate bookkeeping.
#
# Usage:
#   claim-card.sh <card-number> <short-slug> [base-branch]
#
# Exit codes:
#   0   — claim successful; caller may proceed
#   10  — card already claimed (branch exists on remote); caller must stop
#   20  — git or network error; caller should surface the error
#   30  — bad arguments or missing dependency
#
# Side effects on success:
#   - Creates a local branch `claim/<N>-<slug>` from base (default: remote HEAD).
#   - Pushes it to origin with `--force-with-lease=<ref>:` — pushing only
#     iff the remote ref does not already exist. This is the atomic step.
#   - Writes and commits a marker file at .board-superpowers/claims/<N>.claim.
#   - On success prints the branch name on stdout.
#
# This script is intentionally narrow: it only handles the lock. Moving the
# GitHub Project card to "In Progress" is a separate call (transition-card.sh)
# so that a partial failure here doesn't leave the board inconsistent.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

bsp_require_cmd git 30

# ---- args ----------------------------------------------------------------
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  bsp_show_help; exit 0
fi

CARD_NUMBER="${1:-}"
SLUG="${2:-}"
BASE_BRANCH="${3:-}"

[ -n "$CARD_NUMBER" ] || bsp_die "usage: $BSP_SCRIPT_NAME <card-number> <short-slug> [base-branch]" 30
[ -n "$SLUG" ]        || bsp_die "usage: $BSP_SCRIPT_NAME <card-number> <short-slug> [base-branch]" 30

case "$CARD_NUMBER" in
  ''|*[!0-9]*) bsp_die "card-number must be a positive integer, got: $CARD_NUMBER" 30 ;;
esac

SLUG_CLEAN="$(bsp_sanitize_slug "$SLUG")"
[ -n "$SLUG_CLEAN" ] || bsp_die "slug is empty after sanitization" 30

BRANCH="claim/${CARD_NUMBER}-${SLUG_CLEAN}"

# ---- enter repo root (M1) ------------------------------------------------
GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || bsp_die "not inside a git work tree" 30
cd "$GIT_ROOT"

# ---- determine base branch ----------------------------------------------
if [ -z "$BASE_BRANCH" ]; then
  BASE_BRANCH="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)"
  if [ -z "$BASE_BRANCH" ]; then
    if git show-ref --verify --quiet refs/remotes/origin/main; then
      BASE_BRANCH="main"
    elif git show-ref --verify --quiet refs/remotes/origin/master; then
      BASE_BRANCH="master"
    else
      bsp_die "cannot determine base branch; pass it as the 3rd argument" 20
    fi
  fi
fi

git check-ref-format --branch "$BASE_BRANCH" >/dev/null 2>&1 \
  || bsp_die "invalid base branch: $BASE_BRANCH" 20

# ---- fetch + early "already claimed" check ------------------------------
git fetch origin --quiet 2>/dev/null || bsp_die "git fetch failed" 20

if git show-ref --verify --quiet "refs/remotes/origin/${BRANCH}"; then
  LAST_AUTHOR="$(git log -1 --format='%an <%ae>' "origin/${BRANCH}" 2>/dev/null || printf 'unknown')"
  LAST_DATE="$(git log -1 --format='%ar'        "origin/${BRANCH}" 2>/dev/null || printf 'unknown')"
  {
    printf 'card #%s already claimed\n' "$CARD_NUMBER"
    printf '  branch:      %s\n' "$BRANCH"
    printf '  last author: %s\n' "$LAST_AUTHOR"
    printf '  last commit: %s\n' "$LAST_DATE"
  } >&2
  exit 10
fi

# ---- create or resume local branch --------------------------------------
if git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
  # H2 fix: refuse to reset if the branch carries unpushed commits.
  AHEAD="$(git rev-list --count "origin/${BASE_BRANCH}..${BRANCH}" 2>/dev/null || printf '0')"
  if [ "$AHEAD" != "0" ]; then
    bsp_die "local branch '$BRANCH' has $AHEAD unpushed commit(s); refusing to reset. Push, delete, or rename it, then retry." 20
  fi
  if [ -n "$(git status --porcelain 2>/dev/null || true)" ]; then
    bsp_die "local branch '$BRANCH' has uncommitted changes; refusing to reset. Commit, stash, or clean, then retry." 20
  fi
  git checkout --quiet "$BRANCH" 2>/dev/null \
    || bsp_die "git checkout '$BRANCH' failed" 20
  git reset --hard --quiet "origin/${BASE_BRANCH}" \
    || bsp_die "git reset --hard origin/${BASE_BRANCH} failed" 20
else
  git checkout --quiet -b "$BRANCH" "origin/${BASE_BRANCH}" 2>/dev/null \
    || bsp_die "git checkout -b '$BRANCH' 'origin/${BASE_BRANCH}' failed" 20
fi

# ---- write claim marker and commit --------------------------------------
SESSION_SLUG="${BOARD_SP_SESSION_SLUG:-s-$(date +%s)-$$}"
MARKER_FILE=".board-superpowers/claims/${CARD_NUMBER}.claim"
mkdir -p ".board-superpowers/claims" \
  || bsp_die "failed to create .board-superpowers/claims" 20

{
  printf 'card: %s\n' "$CARD_NUMBER"
  printf 'session: %s\n' "$SESSION_SLUG"
  printf 'claimed_at: %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  printf 'base: %s\n' "$BASE_BRANCH"
  printf 'branch: %s\n' "$BRANCH"
} > "$MARKER_FILE" || bsp_die "failed to write $MARKER_FILE" 20

# -f is required: bootstrap-project.sh places `.board-superpowers/claims/`
# into .gitignore (per-session state), but the claim branch MUST carry
# the marker commit — that commit + push IS the atomic lock.
git add -f "$MARKER_FILE" >/dev/null 2>&1 \
  || bsp_die "git add -f $MARKER_FILE failed" 20

COMMIT_MSG="claim: card #${CARD_NUMBER} [${SESSION_SLUG}]

Automated claim commit from board-superpowers. The presence of this
branch on the remote means a Board Consumer session owns card
#${CARD_NUMBER}. To release the claim, delete the branch on the remote."

git commit --quiet -m "$COMMIT_MSG" >/dev/null 2>&1 \
  || bsp_die "git commit failed" 20

# ---- atomic push (the actual lock) --------------------------------------
# --force-with-lease=<ref>:  (empty expected value) → push only iff remote
# ref does not exist. Atomic against concurrent creators.
PUSH_OUT=""
set +e
PUSH_OUT="$(git push --force-with-lease="refs/heads/${BRANCH}:" \
                     --set-upstream origin "$BRANCH" 2>&1)"
PUSH_RC=$?
set -e

if [ "$PUSH_RC" -eq 0 ]; then
  printf '%s\n' "$BRANCH"
  exit 0
fi

# ---- push failed: attempt cleanup, then disambiguate ---------------------
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || printf '')"
if [ "$CURRENT_BRANCH" = "$BRANCH" ]; then
  git checkout --quiet "$BASE_BRANCH" 2>/dev/null \
    || git checkout --quiet "origin/${BASE_BRANCH}" 2>/dev/null \
    || true
fi
git branch -D "$BRANCH" >/dev/null 2>&1 || true
git fetch origin --quiet 2>/dev/null || true

if git show-ref --verify --quiet "refs/remotes/origin/${BRANCH}"; then
  printf 'card #%s was just claimed by another session (race)\n' "$CARD_NUMBER" >&2
  exit 10
fi

# Surface the actual git output so the caller can diagnose auth/network/
# permission problems instead of guessing.
{
  printf '%s: error: git push failed; check auth / network\n' "$BSP_SCRIPT_NAME"
  printf '  git output:\n'
  printf '%s\n' "$PUSH_OUT" | sed 's/^/    /'
} >&2
exit 20
