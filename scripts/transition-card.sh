#!/usr/bin/env bash
# board-superpowers / transition-card.sh
#
# Move a card to a new Status column on a GitHub Project v2.
#
# Usage:
#   transition-card.sh --issue <N> --project OWNER/NUMBER --to "In Progress" [--repo OWNER/REPO]
#
# Exit codes:
#   0  — success
#   1  — operational failure (project not found, status option missing, etc.)
#   2  — bad arguments
#   3  — missing dependency (gh, python3)
#
# Requires: gh CLI with `project` scope, python3 (for JSON parsing).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

bsp_require_cmd gh
bsp_require_cmd python3

ISSUE=""
PROJECT=""
TO_STATUS=""
REPO=""

while [ $# -gt 0 ]; do
  case "$1" in
    --issue)   bsp_require_arg --issue   "$#"; ISSUE="$2";     shift 2 ;;
    --project) bsp_require_arg --project "$#"; PROJECT="$2";   shift 2 ;;
    --to)      bsp_require_arg --to      "$#"; TO_STATUS="$2"; shift 2 ;;
    --repo)    bsp_require_arg --repo    "$#"; REPO="$2";      shift 2 ;;
    -h|--help) bsp_show_help; exit 0 ;;
    *) bsp_die "unknown argument: $1" 2 ;;
  esac
done

[ -n "$ISSUE" ]     || bsp_die "missing --issue" 2
[ -n "$PROJECT" ]   || bsp_die "missing --project" 2
[ -n "$TO_STATUS" ] || bsp_die "missing --to" 2

case "$ISSUE" in
  ''|*[!0-9]*) bsp_die "--issue must be a positive integer, got: $ISSUE" 2 ;;
esac

bsp_parse_owner_number "$PROJECT" --project
OWNER="$BSP_OWNER"
NUMBER="$BSP_NUMBER"

REPO_FULL=""
if [ -n "$REPO" ]; then
  # Validates format and exposes BSP_REPO_OWNER + BSP_REPO_NAME for logging.
  bsp_parse_owner_repo "$REPO" --repo
  # gh project item-list returns content.repository as "owner/repo", so we
  # must compare against the full value, not just the repo name. (Original
  # scripts compared against `${REPO##*/}` which never matched.)
  REPO_FULL="$REPO"
fi

# ----- Resolve the project node id ----------------------------------------
if ! PROJECT_ID="$(gh project view "$NUMBER" --owner "$OWNER" --format json --jq '.id' 2>&1)"; then
  bsp_die "gh project view failed: $PROJECT_ID"
fi
[ -n "$PROJECT_ID" ] || bsp_die "project $PROJECT returned empty id"

# ----- Resolve the item id for the issue ----------------------------------
# Identifiers are passed through environment — never string-interpolated
# into code (was CVE-grade injection before: H1/L3).
if ! ITEM_JSON="$(gh project item-list "$NUMBER" --owner "$OWNER" --format json --limit 500 2>&1)"; then
  bsp_die "gh project item-list failed: $ITEM_JSON"
fi

ITEM_ID="$(
  printf '%s' "$ITEM_JSON" \
    | ISSUE_NUM="$ISSUE" REPO_FULL="$REPO_FULL" python3 -c '
import json, os, sys
issue_num = int(os.environ["ISSUE_NUM"])
repo_full = os.environ.get("REPO_FULL", "")
try:
    d = json.load(sys.stdin)
except Exception as e:
    print("json parse error:", e, file=sys.stderr)
    sys.exit(2)
for item in d.get("items", []):
    c = item.get("content") or {}
    if c.get("number") != issue_num:
        continue
    if repo_full and c.get("repository") != repo_full:
        continue
    print(item.get("id", ""))
    break
'
)" || bsp_die "failed to parse project items JSON"

[ -n "$ITEM_ID" ] || bsp_die "issue #$ISSUE is not on project $PROJECT"

# ----- Resolve Status field + target option id ----------------------------
if ! FIELD_JSON="$(gh project field-list "$NUMBER" --owner "$OWNER" --format json 2>&1)"; then
  bsp_die "gh project field-list failed: $FIELD_JSON"
fi

FIELD_ID="$(
  printf '%s' "$FIELD_JSON" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception as e:
    print("json parse error:", e, file=sys.stderr)
    sys.exit(2)
for f in d.get("fields", []):
    if f.get("name") == "Status":
        print(f.get("id", ""))
        break
'
)" || bsp_die "failed to parse fields JSON"

[ -n "$FIELD_ID" ] || bsp_die "project has no Status field"

OPTION_ID="$(
  printf '%s' "$FIELD_JSON" | TO_STATUS="$TO_STATUS" python3 -c '
import json, os, sys
want = os.environ["TO_STATUS"].strip().lower()
try:
    d = json.load(sys.stdin)
except Exception as e:
    print("json parse error:", e, file=sys.stderr)
    sys.exit(2)
for f in d.get("fields", []):
    if f.get("name") == "Status":
        for o in f.get("options", []):
            if o.get("name", "").strip().lower() == want:
                print(o.get("id", ""))
                break
        break
'
)" || bsp_die "failed to parse options JSON"

if [ -z "$OPTION_ID" ]; then
  {
    printf '%s: error: project Status field has no option named: %s\n' \
      "$BSP_SCRIPT_NAME" "$TO_STATUS"
    printf '  available options:\n'
    printf '%s' "$FIELD_JSON" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for f in d.get("fields", []):
    if f.get("name") == "Status":
        for o in f.get("options", []):
            print("    -", o.get("name", ""))
        break
'
  } >&2
  exit 1
fi

# ----- Execute the mutation -----------------------------------------------
if ! gh project item-edit \
       --id "$ITEM_ID" \
       --field-id "$FIELD_ID" \
       --project-id "$PROJECT_ID" \
       --single-select-option-id "$OPTION_ID" >/dev/null 2>&1; then
  bsp_die "gh project item-edit failed"
fi

printf 'moved issue #%s to %s\n' "$ISSUE" "$TO_STATUS"
