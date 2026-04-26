#!/usr/bin/env bash
# scripts/read-board.sh — list cards from a GitHub Project, JSON output.
#
# Called by managing-board (F-01 daily, F-08 intake) and consuming-card
# (F-C0 manual pull) skills.
#
# Args:
#   --owner <login>      GitHub org or user that owns the Project
#   --project <number>   Project number
#   --status <name>      Optional: filter by Status field value
#                        (Backlog / Ready / In Progress / Blocked /
#                        In Review / Done)
#
# Stdout: JSON array of card summaries:
#   [{"number": 12, "title": "...", "status": "Ready", "url": "..."}, ...]
#
# Exit codes:
#   0 — success (even with empty array)
#   1 — bad args / gh failure / parse error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
# shellcheck source-path=SCRIPTDIR
. "${SCRIPT_DIR}/lib/common.sh"

OWNER=""
PROJECT=""
STATUS=""

while [ $# -gt 0 ]; do
    case "$1" in
        --owner)   OWNER="$2";   shift 2 ;;
        --project) PROJECT="$2"; shift 2 ;;
        --status)  STATUS="$2";  shift 2 ;;
        *) bsp_die "unknown arg: $1" ;;
    esac
done

[ -n "${OWNER}" ]   || bsp_die "missing --owner"
[ -n "${PROJECT}" ] || bsp_die "missing --project"

bsp_require_cmd gh
bsp_require_cmd python3

# Pull all items, then filter in python (gh project item-list has no
# server-side status filter as of gh 2.x).
gh project item-list "${PROJECT}" --owner "${OWNER}" --format json --limit 200 \
    | python3 -c "
import json, sys
data = json.load(sys.stdin)
items = data.get('items', [])
status_filter = sys.argv[1] if len(sys.argv) > 1 else ''
out = []
for it in items:
    content = it.get('content', {}) or {}
    # Issues only — skip draft items + PRs in v1-minimum.
    if content.get('type') != 'Issue':
        continue
    status = it.get('status', '')
    if status_filter and status != status_filter:
        continue
    out.append({
        'number': content.get('number'),
        'title': content.get('title'),
        'status': status,
        'url': content.get('url'),
        'item_id': it.get('id'),
    })
print(json.dumps(out, ensure_ascii=False, indent=2))
" "${STATUS}"
