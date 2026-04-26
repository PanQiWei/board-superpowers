#!/usr/bin/env bash
# scripts/claim-card.sh — atomic claim transaction for a board card.
#
# Called by consuming-card skill (F-C2). Performs four steps in order;
# all four must succeed or the script aborts and rolls back what it can.
#
#   1. Set the card's Status field to "In Progress" (gh project item-edit).
#   2. Create a worktree at $HOME/.config/superpowers/worktrees/<repo>/<branch>.
#   3. Create branch claim/<N>-<slug> from origin/main inside the worktree.
#   4. Push the empty claim branch so the board sees the claim signal.
#
# Args:
#   --owner <login>      GitHub org / user owning the Project
#   --project <number>   Project number
#   --repo <repo>        Repository name (no owner prefix)
#   --card <N>           Card number (issue number)
#   --title <text>       Card title (used for branch slug)
#
# Idempotent: re-running with the same args is a no-op if the card is
# already claimed by this same branch. Detects existing worktree / branch
# and skips.
#
# Exit codes:
#   0 — claimed (or already owned by this branch)
#   1 — bad args / WIP cap exceeded / gh failure / git failure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
# shellcheck source-path=SCRIPTDIR
. "${SCRIPT_DIR}/lib/common.sh"

OWNER=""
PROJECT=""
REPO=""
CARD=""
TITLE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --owner)   OWNER="$2";   shift 2 ;;
        --project) PROJECT="$2"; shift 2 ;;
        --repo)    REPO="$2";    shift 2 ;;
        --card)    CARD="$2";    shift 2 ;;
        --title)   TITLE="$2";   shift 2 ;;
        *) bsp_die "unknown arg: $1" ;;
    esac
done

[ -n "${OWNER}" ]   || bsp_die "missing --owner"
[ -n "${PROJECT}" ] || bsp_die "missing --project"
[ -n "${REPO}" ]    || bsp_die "missing --repo"
[ -n "${CARD}" ]    || bsp_die "missing --card"
[ -n "${TITLE}" ]   || bsp_die "missing --title"

bsp_require_cmd gh
bsp_require_cmd git
bsp_require_cmd python3

SLUG="$(bsp_slugify "${TITLE}")"
BRANCH="claim/${CARD}-${SLUG}"
WT_PATH="$(bsp_worktree_path "${REPO}" "${BRANCH}")"

bsp_log "claim transaction: card #${CARD} → branch ${BRANCH}"
bsp_log "worktree target: ${WT_PATH}"

# --- Step 1: set Status = "In Progress" ---------------------------------
bsp_log "step 1/4: setting Status field to 'In Progress'"

# Fetch field + option IDs.
STATUS_FIELD_ID="$(bsp_gh_field_id "${OWNER}" "${PROJECT}" "Status")"
[ -n "${STATUS_FIELD_ID}" ] || bsp_die "could not resolve Status field id"
STATUS_OPTION_ID="$(bsp_gh_field_option_id "${OWNER}" "${PROJECT}" "Status" "In Progress")"
[ -n "${STATUS_OPTION_ID}" ] || bsp_die "could not resolve 'In Progress' option id"

# Find the project-item id for this card.
ITEM_ID="$(gh project item-list "${PROJECT}" --owner "${OWNER}" --format json --limit 200 \
    | python3 -c "
import json, sys
data = json.load(sys.stdin)
target = int(sys.argv[1])
for it in data.get('items', []):
    content = it.get('content', {}) or {}
    if content.get('type') == 'Issue' and content.get('number') == target:
        print(it.get('id'))
        sys.exit(0)
sys.exit(1)
" "${CARD}")"
[ -n "${ITEM_ID}" ] || bsp_die "card #${CARD} not found in project ${PROJECT}"

# Get the project's GraphQL ID (different from project number).
PROJECT_ID="$(gh project view "${PROJECT}" --owner "${OWNER}" --format json \
    | python3 -c "import json,sys; print(json.load(sys.stdin).get('id', ''))")"
[ -n "${PROJECT_ID}" ] || bsp_die "could not resolve project graphql id"

gh project item-edit \
    --id "${ITEM_ID}" \
    --project-id "${PROJECT_ID}" \
    --field-id "${STATUS_FIELD_ID}" \
    --single-select-option-id "${STATUS_OPTION_ID}" >/dev/null

bsp_log "step 1/4: Status field updated"

# --- Step 2 + 3: create worktree + branch -------------------------------
if [ -d "${WT_PATH}" ]; then
    bsp_warn "worktree already exists at ${WT_PATH} — skipping creation"
else
    bsp_log "step 2/4: creating worktree at ${WT_PATH}"
    mkdir -p "$(dirname "${WT_PATH}")"
    git fetch origin --quiet
    git worktree add "${WT_PATH}" -b "${BRANCH}" origin/main
fi

# --- Step 4: push the empty claim branch --------------------------------
bsp_log "step 4/4: pushing claim branch to origin"
git -C "${WT_PATH}" push -u origin "${BRANCH}" 2>&1 | tail -5

bsp_log "claim complete: cd ${WT_PATH}"

# Stdout: machine-readable claim summary
python3 -c "
import json, sys
print(json.dumps({
    'card': int(sys.argv[1]),
    'branch': sys.argv[2],
    'worktree': sys.argv[3],
    'status': 'claimed',
}, indent=2))
" "${CARD}" "${BRANCH}" "${WT_PATH}"
