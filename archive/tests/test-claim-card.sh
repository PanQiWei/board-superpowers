#!/usr/bin/env bash
# tests/test-claim-card.sh
#
# Regression test for scripts/claim-card.sh.
#
# Purpose: ensure the claim marker is force-added onto the claim branch
# so the claim commit + atomic push succeed even when the bootstrap has
# put `.board-superpowers/claims/` in `.gitignore` (the default layout).
#
# Without `git add -f`, `git add` refuses to stage ignored paths; the
# script dies at exit code 20 and no remote branch is ever created,
# meaning the plugin's atomic-lock mechanism is silently non-functional.
# That failure mode is the specific regression this test guards against.
#
# Design notes:
#   - Runs in a fresh temp directory (trap-cleaned on exit).
#   - Uses GIT_CONFIG_GLOBAL / GIT_CONFIG_SYSTEM to isolate from the
#     developer's real git config (identity, hooks, GPG signing).
#   - Seeds the working repo to mirror post-bootstrap state: a main
#     branch with a .gitignore that ignores the claims directory.
#   - Uses a bare local repo as "origin" so the test is hermetic (no
#     network).
#
# Exit codes: 0 on pass, 1 on any assertion failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLAIM_SCRIPT="$REPO_ROOT/scripts/claim-card.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[ -f "$CLAIM_SCRIPT" ] || fail "claim-card.sh not found at $CLAIM_SCRIPT"

TMP="$(mktemp -d -t bsp-test-claim-XXXXXXXX)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# Full environment isolation. Setting HOME + XDG_CONFIG_HOME keeps git from
# reading the developer's ~/.gitconfig, ~/.config/git/{config,ignore},
# ~/.config/git/attributes, etc. — any one of which could silently change
# `git add` behavior. GIT_CONFIG_GLOBAL/SYSTEM isolates the config file
# lookups; core.excludesFile=/dev/null blocks the global ignore path.
mkdir -p "$TMP/home" "$TMP/xdg"
export HOME="$TMP/home"
export XDG_CONFIG_HOME="$TMP/xdg"
export GIT_CONFIG_GLOBAL="$TMP/.gitconfig-global"
export GIT_CONFIG_SYSTEM=/dev/null
# Block any prompts in case a future refactor reaches a real remote.
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=/bin/false
export SSH_ASKPASS=/bin/false
export GCM_INTERACTIVE=never

: > "$GIT_CONFIG_GLOBAL"
git config --file "$GIT_CONFIG_GLOBAL" user.name         "BSP Test Runner"
git config --file "$GIT_CONFIG_GLOBAL" user.email        "test@board-superpowers.invalid"
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
git config --file "$GIT_CONFIG_GLOBAL" commit.gpgsign    false
git config --file "$GIT_CONFIG_GLOBAL" core.hooksPath    /dev/null
git config --file "$GIT_CONFIG_GLOBAL" core.excludesFile /dev/null

REMOTE="$TMP/remote.git"
WORK="$TMP/work"

git init --bare --quiet "$REMOTE"

git init --quiet -b main "$WORK"
cd "$WORK"
cat > .gitignore <<EOF
# board-superpowers local state (claim markers are per-session)
.board-superpowers/claims/
EOF
printf '# fixture repo\n' > README.md
git add .gitignore README.md
git commit --quiet -m "initial"
git remote add origin "$REMOTE"
git push --quiet -u origin main

# claim-card.sh resolves the base branch via refs/remotes/origin/HEAD;
# set-head makes that resolvable in a fresh clone-free setup.
git remote set-head origin main >/dev/null

CARD=42
SLUG="test-slug"
BRANCH="claim/${CARD}-${SLUG}"
MARKER_PATH=".board-superpowers/claims/${CARD}.claim"
export BOARD_SP_SESSION_SLUG="s-test"

set +e
OUT="$(bash "$CLAIM_SCRIPT" "$CARD" "$SLUG" 2>&1)"
RC=$?
set -e

if [ "$RC" -ne 0 ]; then
  printf 'FAIL: claim-card.sh exited %s\n' "$RC" >&2
  printf -- '--- script output ---\n%s\n' "$OUT" >&2
  exit 1
fi

# Contract: on success, claim-card.sh prints two key=value lines —
# `branch=<name>` and `worktree=<absolute path>`. Guard the public
# interface; callers parse this (see skills/consuming-card/SKILL.md
# Step 2). This test only asserts the branch line matches; worktree
# isolation has its own harness (tests/test-claim-card-worktree.sh).
OUT_BRANCH="$(printf '%s\n' "$OUT" | sed -n '1s/^branch=//p')"
if [ "$OUT_BRANCH" != "$BRANCH" ]; then
  printf 'FAIL: expected first line "branch=%s", full stdout was %q\n' \
    "$BRANCH" "$OUT" >&2
  exit 1
fi

git fetch --quiet origin

if ! git ls-remote --exit-code origin "refs/heads/${BRANCH}" >/dev/null 2>&1; then
  fail "remote is missing ${BRANCH} after claim"
fi

if ! git ls-tree -r --name-only "origin/${BRANCH}" | grep -Fxq "$MARKER_PATH"; then
  printf 'FAIL: %s is not tracked on origin/%s\n' "$MARKER_PATH" "$BRANCH" >&2
  printf -- '--- tracked files on origin/%s ---\n' "$BRANCH" >&2
  git ls-tree -r --name-only "origin/${BRANCH}" >&2
  exit 1
fi

MARKER_CONTENT="$(git show "origin/${BRANCH}:${MARKER_PATH}")"
printf '%s\n' "$MARKER_CONTENT" | grep -q "^card: ${CARD}$" \
  || { printf 'FAIL: marker missing expected card line\n---\n%s\n' "$MARKER_CONTENT" >&2; exit 1; }
printf '%s\n' "$MARKER_CONTENT" | grep -q "^session: s-test$" \
  || { printf 'FAIL: marker missing expected session line\n---\n%s\n' "$MARKER_CONTENT" >&2; exit 1; }

printf 'PASS: claim-card.sh commits the marker despite .gitignore\n'
