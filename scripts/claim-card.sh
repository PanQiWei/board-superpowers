#!/usr/bin/env bash
# board-superpowers / claim-card.sh
#
# Atomically claim a GitHub Project card AND create an isolated git
# worktree for the Consumer session.
#
# Two independent guarantees, both essential:
#
#  1. Distributed lock via `git push` on a namespaced claim branch.
#     Creating a remote branch is atomic in git — if two sessions race
#     to push the same new branch, exactly one wins. The winner holds
#     the claim; the loser exits cleanly.
#
#  2. Filesystem isolation via a dedicated git worktree. Parallel
#     Consumer sessions cannot share the repo's primary working tree
#     without clobbering each other's HEAD / WIP. Each session gets a
#     distinct worktree, created fresh from the base branch.
#
# The claim branch IS the feature branch AND the worktree's branch.
# No separate bookkeeping.
#
# Usage:
#   claim-card.sh <card-number> <short-slug> [base-branch]
#
# Exit codes:
#   0   — claim successful; worktree ready; caller may proceed
#   10  — card already claimed (branch exists on remote); caller must stop
#   20  — git or network error (including worktree setup); caller should
#         surface the error and not retry automatically
#   30  — bad arguments or missing dependency
#
# Stdout on success (two lines, in this order):
#   branch=<claim branch name>
#   worktree=<absolute path to worktree>
#
# Side effects on success:
#   - New local branch `claim/<N>-<slug>` based on origin/<base>.
#   - New worktree checked out at:
#       * $BOARD_SP_WORKTREE_DIR/<branch>                       (if env set), OR
#       * <primary_root>/.worktrees/<branch>                    (if .worktrees/
#                                                                 exists AND is
#                                                                 gitignored), OR
#       * $HOME/.config/superpowers/worktrees/<project>/<branch>
#         (default — global, outside repo, no gitignore concern).
#   - `.board-superpowers/claims/<N>.claim` force-committed inside the
#     worktree (marker file must exist on the claim branch even though
#     the directory is gitignored for local-state isolation).
#   - `git push --force-with-lease=<ref>:` — pushing only iff the remote
#     ref does not already exist. This is the atomic lock step.
#
# This script does NOT:
#   - Move the GitHub Project card to "In Progress". That is
#     transition-card.sh's job so a partial failure here doesn't leave
#     the board inconsistent.
#   - Clean up worktrees after merge. See docs/consuming-card for the
#     manual `git worktree remove` command. Automation is a future card.

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

# ---- resolve primary checkout -------------------------------------------
# Script may be invoked from any worktree. `git rev-parse --git-common-dir`
# gives the shared `.git` directory regardless of cwd; its parent is the
# primary working tree.
GIT_COMMON_DIR="$(git rev-parse --git-common-dir 2>/dev/null)" \
  || bsp_die "not inside a git work tree" 30
# --git-common-dir may return a relative path; resolve to absolute.
GIT_COMMON_DIR="$(cd "$GIT_COMMON_DIR" && pwd)"
PRIMARY_ROOT="$(cd "$GIT_COMMON_DIR/.." && pwd)"
PROJECT_NAME="$(basename "$PRIMARY_ROOT")"

# ---- determine base branch ---------------------------------------------
if [ -z "$BASE_BRANCH" ]; then
  BASE_BRANCH="$(git -C "$PRIMARY_ROOT" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null \
                  | sed 's|^origin/||' || true)"
  if [ -z "$BASE_BRANCH" ]; then
    if git -C "$PRIMARY_ROOT" show-ref --verify --quiet refs/remotes/origin/main; then
      BASE_BRANCH="main"
    elif git -C "$PRIMARY_ROOT" show-ref --verify --quiet refs/remotes/origin/master; then
      BASE_BRANCH="master"
    else
      bsp_die "cannot determine base branch; pass it as the 3rd argument" 20
    fi
  fi
fi

git -C "$PRIMARY_ROOT" check-ref-format --branch "$BASE_BRANCH" >/dev/null 2>&1 \
  || bsp_die "invalid base branch: $BASE_BRANCH" 20

# ---- fetch + early "already claimed" check ------------------------------
git -C "$PRIMARY_ROOT" fetch origin --quiet 2>/dev/null \
  || bsp_die "git fetch failed" 20

if git -C "$PRIMARY_ROOT" show-ref --verify --quiet "refs/remotes/origin/${BRANCH}"; then
  LAST_AUTHOR="$(git -C "$PRIMARY_ROOT" log -1 --format='%an <%ae>' "origin/${BRANCH}" 2>/dev/null || printf 'unknown')"
  LAST_DATE="$(git -C "$PRIMARY_ROOT" log -1 --format='%ar'        "origin/${BRANCH}" 2>/dev/null || printf 'unknown')"
  {
    printf 'card #%s already claimed\n' "$CARD_NUMBER"
    printf '  branch:      %s\n' "$BRANCH"
    printf '  last author: %s\n' "$LAST_AUTHOR"
    printf '  last commit: %s\n' "$LAST_DATE"
  } >&2
  exit 10
fi

# ---- pick worktree directory --------------------------------------------
# Priority:
#   1. $BOARD_SP_WORKTREE_DIR — explicit absolute path override.
#   2. <primary>/.worktrees/ if it exists AND is gitignored.
#   3. $HOME/.config/superpowers/worktrees/<project>/  (global default).
#
# #2's gitignore check protects against a .worktrees/ that isn't yet
# ignored — rather than silently polluting `git status`, fall through
# to the global default.
bsp_pick_worktree_dir() {
  if [ -n "${BOARD_SP_WORKTREE_DIR:-}" ]; then
    case "$BOARD_SP_WORKTREE_DIR" in
      /*) : ;; # absolute, ok
      *)  bsp_die "BOARD_SP_WORKTREE_DIR must be absolute, got: $BOARD_SP_WORKTREE_DIR" 30 ;;
    esac
    printf '%s\n' "$BOARD_SP_WORKTREE_DIR"
    return 0
  fi

  if [ -d "$PRIMARY_ROOT/.worktrees" ]; then
    if git -C "$PRIMARY_ROOT" check-ignore -q .worktrees 2>/dev/null; then
      printf '%s\n' "$PRIMARY_ROOT/.worktrees"
      return 0
    fi
    bsp_log "warning: $PRIMARY_ROOT/.worktrees exists but is not gitignored — falling back to global worktree dir"
  fi

  printf '%s\n' "$HOME/.config/superpowers/worktrees/$PROJECT_NAME"
}

WORKTREE_DIR="$(bsp_pick_worktree_dir)"
WORKTREE_PATH="$WORKTREE_DIR/$BRANCH"

# ---- idempotent reuse if a matching worktree already exists -------------
# Useful if the previous run got as far as creating the worktree but
# failed before the push. Re-running completes the claim without manual
# cleanup.
if [ -e "$WORKTREE_PATH" ]; then
  if git -C "$PRIMARY_ROOT" worktree list --porcelain 2>/dev/null \
       | grep -Fxq "worktree $WORKTREE_PATH"; then
    EXISTING_HEAD="$(git -C "$WORKTREE_PATH" rev-parse --abbrev-ref HEAD 2>/dev/null || printf '')"
    if [ "$EXISTING_HEAD" = "$BRANCH" ] && [ -f "$WORKTREE_PATH/.board-superpowers/claims/${CARD_NUMBER}.claim" ]; then
      # Looks like the marker is already there. Attempt to push (re-entrant).
      set +e
      git -C "$WORKTREE_PATH" push --force-with-lease="refs/heads/${BRANCH}:" \
                                    --set-upstream origin "$BRANCH" >/dev/null 2>&1
      RESUME_RC=$?
      set -e
      if [ "$RESUME_RC" -eq 0 ]; then
        printf 'branch=%s\n' "$BRANCH"
        printf 'worktree=%s\n' "$WORKTREE_PATH"
        exit 0
      fi
      # Push failed on re-entry → treat as error path below.
    fi
  fi
  bsp_die "worktree path already exists and does not match a resumable claim: $WORKTREE_PATH" 20
fi

mkdir -p "$WORKTREE_DIR" \
  || bsp_die "failed to create worktree parent dir: $WORKTREE_DIR" 20

# ---- cleanup helper (used on push failure) ------------------------------
# Removes a newly-created worktree and its local branch so the caller can
# retry without manual housekeeping. Swallows all errors — cleanup must
# never mask the original failure.
bsp_cleanup_partial_claim() {
  local path="$1"
  local branch="$2"
  git -C "$PRIMARY_ROOT" worktree remove --force "$path" >/dev/null 2>&1 || true
  # Belt-and-suspenders: remove prunable entries.
  git -C "$PRIMARY_ROOT" worktree prune >/dev/null 2>&1 || true
  git -C "$PRIMARY_ROOT" branch -D "$branch" >/dev/null 2>&1 || true
}

# ---- create worktree with new branch ------------------------------------
# Base on origin/<base-branch> so local uncommitted state cannot leak into
# the new worktree. `-b` creates the branch in the same step.
if ! git -C "$PRIMARY_ROOT" worktree add "$WORKTREE_PATH" \
       -b "$BRANCH" "origin/${BASE_BRANCH}" >/dev/null 2>&1; then
  bsp_cleanup_partial_claim "$WORKTREE_PATH" "$BRANCH"
  bsp_die "git worktree add '$WORKTREE_PATH' -b '$BRANCH' 'origin/${BASE_BRANCH}' failed" 20
fi

# ---- write claim marker in the new worktree -----------------------------
SESSION_SLUG="${BOARD_SP_SESSION_SLUG:-s-$(date +%s)-$$}"
MARKER_REL=".board-superpowers/claims/${CARD_NUMBER}.claim"
MARKER_ABS="$WORKTREE_PATH/$MARKER_REL"

mkdir -p "$(dirname "$MARKER_ABS")" || {
  bsp_cleanup_partial_claim "$WORKTREE_PATH" "$BRANCH"
  bsp_die "failed to create $(dirname "$MARKER_REL") inside worktree" 20
}

{
  printf 'card: %s\n' "$CARD_NUMBER"
  printf 'session: %s\n' "$SESSION_SLUG"
  printf 'claimed_at: %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  printf 'base: %s\n' "$BASE_BRANCH"
  printf 'branch: %s\n' "$BRANCH"
  printf 'worktree: %s\n' "$WORKTREE_PATH"
} > "$MARKER_ABS" || {
  bsp_cleanup_partial_claim "$WORKTREE_PATH" "$BRANCH"
  bsp_die "failed to write $MARKER_REL" 20
}

# -f is required: bootstrap-project.sh places `.board-superpowers/claims/`
# into .gitignore (per-session state), but the claim branch MUST carry
# the marker commit — that commit + push IS the atomic lock.
if ! git -C "$WORKTREE_PATH" add -f "$MARKER_REL" >/dev/null 2>&1; then
  bsp_cleanup_partial_claim "$WORKTREE_PATH" "$BRANCH"
  bsp_die "git add -f $MARKER_REL failed" 20
fi

COMMIT_MSG="claim: card #${CARD_NUMBER} [${SESSION_SLUG}]

Automated claim commit from board-superpowers. The presence of this
branch on the remote means a Board Consumer session owns card
#${CARD_NUMBER}. To release the claim, delete the branch on the remote."

if ! git -C "$WORKTREE_PATH" commit --quiet -m "$COMMIT_MSG" >/dev/null 2>&1; then
  bsp_cleanup_partial_claim "$WORKTREE_PATH" "$BRANCH"
  bsp_die "git commit failed" 20
fi

# ---- atomic push (the actual lock) --------------------------------------
# --force-with-lease=<ref>:  (empty expected value) → push only iff remote
# ref does not exist. Atomic against concurrent creators.
PUSH_OUT=""
set +e
PUSH_OUT="$(git -C "$WORKTREE_PATH" push --force-with-lease="refs/heads/${BRANCH}:" \
                                          --set-upstream origin "$BRANCH" 2>&1)"
PUSH_RC=$?
set -e

if [ "$PUSH_RC" -eq 0 ]; then
  printf 'branch=%s\n' "$BRANCH"
  printf 'worktree=%s\n' "$WORKTREE_PATH"
  exit 0
fi

# ---- push failed: cleanup, then disambiguate ----------------------------
bsp_cleanup_partial_claim "$WORKTREE_PATH" "$BRANCH"
git -C "$PRIMARY_ROOT" fetch origin --quiet 2>/dev/null || true

if git -C "$PRIMARY_ROOT" show-ref --verify --quiet "refs/remotes/origin/${BRANCH}"; then
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
