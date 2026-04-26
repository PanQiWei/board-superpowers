#!/usr/bin/env bash
# board-superpowers / create-card.sh
#
# Create a GitHub Issue with the board-superpowers standard body and add it
# to the configured GitHub Project. Used by the Board Manager session during
# decomposition.
#
# Usage:
#   create-card.sh --title "..." --body-file PATH --project OWNER/NUMBER [--repo OWNER/REPO] [--label L ...]
#
# Exit codes:
#   0  — success (issue number printed on stdout)
#   1  — operational failure (issue created but project-add failed, or similar)
#   2  — bad arguments
#   3  — missing dependency (gh)
#
# Requires: gh CLI authenticated with `project` scope.
#
# Note: does NOT pass --project to `gh issue create`. That flag expects a
# project TITLE, not OWNER/NUMBER, and the scripts here consistently speak
# OWNER/NUMBER. We create the issue first, then add it to the project via
# `gh project item-add`, which accepts --owner + NUMBER + --url.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

bsp_require_cmd gh

TITLE=""
BODY_FILE=""
PROJECT=""
REPO=""
LABELS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --title)     bsp_require_arg --title     "$#"; TITLE="$2";     shift 2 ;;
    --body-file) bsp_require_arg --body-file "$#"; BODY_FILE="$2"; shift 2 ;;
    --project)   bsp_require_arg --project   "$#"; PROJECT="$2";   shift 2 ;;
    --repo)      bsp_require_arg --repo      "$#"; REPO="$2";      shift 2 ;;
    --label)     bsp_require_arg --label     "$#"; LABELS+=("$2"); shift 2 ;;
    -h|--help)   bsp_show_help; exit 0 ;;
    *) bsp_die "unknown argument: $1" 2 ;;
  esac
done

[ -n "$TITLE" ]     || bsp_die "missing --title" 2
[ -n "$BODY_FILE" ] || bsp_die "missing --body-file" 2
[ -n "$PROJECT" ]   || bsp_die "missing --project" 2
[ -f "$BODY_FILE" ] || bsp_die "body file not found: $BODY_FILE" 2

bsp_parse_owner_number "$PROJECT" --project
PROJECT_OWNER="$BSP_OWNER"
PROJECT_NUMBER="$BSP_NUMBER"

if [ -n "$REPO" ]; then
  bsp_parse_owner_repo "$REPO" --repo
fi

# ---- Build gh issue create arg vector ------------------------------------
CREATE_ARGS=()
[ -n "$REPO" ] && CREATE_ARGS+=(--repo "$REPO")
CREATE_ARGS+=(--title "$TITLE" --body-file "$BODY_FILE")
if [ "${#LABELS[@]}" -gt 0 ]; then
  for l in "${LABELS[@]}"; do
    CREATE_ARGS+=(--label "$l")
  done
fi

# ---- Create the issue ----------------------------------------------------
if ! ISSUE_URL="$(gh issue create "${CREATE_ARGS[@]}" 2>&1)"; then
  bsp_die "gh issue create failed: $ISSUE_URL"
fi
[ -n "$ISSUE_URL" ] || bsp_die "gh issue create returned empty output"

# gh may print additional chatter; grab the last line that looks like a URL.
ISSUE_URL="$(printf '%s' "$ISSUE_URL" | awk '/^https?:\/\//{u=$0} END{print u}')"
[ -n "$ISSUE_URL" ] || bsp_die "could not find issue URL in gh output"

ISSUE_NUM="${ISSUE_URL##*/}"
case "$ISSUE_NUM" in
  ''|*[!0-9]*) bsp_die "failed to parse issue number from URL: $ISSUE_URL" ;;
esac

# ---- Add the issue to the project ----------------------------------------
if ! ADD_OUT="$(gh project item-add "$PROJECT_NUMBER" \
                  --owner "$PROJECT_OWNER" \
                  --url "$ISSUE_URL" 2>&1)"; then
  {
    printf '%s: error: issue #%s created but failed to add to project %s\n' \
      "$BSP_SCRIPT_NAME" "$ISSUE_NUM" "$PROJECT"
    printf '  gh output: %s\n' "$ADD_OUT"
    printf '  issue URL: %s\n' "$ISSUE_URL"
    printf '  fix: gh project item-add %s --owner %s --url %s\n' \
      "$PROJECT_NUMBER" "$PROJECT_OWNER" "$ISSUE_URL"
  } >&2
  exit 1
fi

printf '%s\n' "$ISSUE_NUM"
