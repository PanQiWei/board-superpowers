#!/usr/bin/env bash
# board-superpowers / bootstrap-project.sh
#
# One-time setup for a repo that wants to use board-superpowers.
#
# Called by the using-board-superpowers skill's "Project setup" step after
# the architect supplies OWNER/NUMBER and confirms they want to proceed.
#
# What it does:
#   1. Creates standard labels on the current repo (type:feature, type:bug,
#      type:chore, type:refactor, type:epic, size:XS..L). Skips ones that
#      already exist; aborts on any other gh failure.
#   2. Validates the project exists and has a Status field with all six
#      required options (Backlog, Ready, In Progress, In Review, Done,
#      Blocked). Reports missing options; does NOT create them (Project v2
#      single-select option creation via API needs extra scopes most tokens
#      lack).
#   3. Writes .board-superpowers/config.yml with the project + default WIP.
#   4. Appends .board-superpowers/claims/ to .gitignore (idempotent).
#
# Usage:
#   bootstrap-project.sh --project OWNER/NUMBER [--wip N]
#
# Exit codes:
#   0  — success
#   1  — validation failure (surface to architect, don't retry blindly)
#   2  — bad args
#   3  — gh CLI / python3 unavailable, or gh not authenticated

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

bsp_require_cmd gh
bsp_require_cmd python3

gh auth status >/dev/null 2>&1 \
  || bsp_die "gh CLI not authenticated; run 'gh auth login'" 3

PROJECT=""
WIP="5"

while [ $# -gt 0 ]; do
  case "$1" in
    --project) bsp_require_arg --project "$#"; PROJECT="$2"; shift 2 ;;
    --wip)     bsp_require_arg --wip     "$#"; WIP="$2";     shift 2 ;;
    -h|--help) bsp_show_help; exit 0 ;;
    *) bsp_die "unknown argument: $1" 2 ;;
  esac
done

[ -n "$PROJECT" ] || bsp_die "usage: $BSP_SCRIPT_NAME --project OWNER/NUMBER [--wip N]" 2

case "$WIP" in
  ''|*[!0-9]*) bsp_die "--wip must be a positive integer, got: $WIP" 2 ;;
esac
[ "$WIP" -ge 1 ] || bsp_die "--wip must be at least 1, got: $WIP" 2

bsp_parse_owner_number "$PROJECT" --project
OWNER="$BSP_OWNER"
NUMBER="$BSP_NUMBER"

printf '→ bootstrapping board-superpowers for project %s\n' "$PROJECT"

# ---- Step 1: labels -----------------------------------------------------
printf '→ creating standard labels...\n'

# name | color (hex w/o #) | description
LABELS=(
  "type:feature|0e8a16|A new user-visible capability"
  "type:bug|d73a4a|A defect in existing behavior"
  "type:chore|c5def5|Non-code or infra work (deps, rename, config)"
  "type:refactor|fbca04|Internal restructuring with no behavior change"
  "type:epic|5319e7|A container for several vertical-slice cards"
  "size:XS|cccccc|Under 50 LOC / 1-2 files"
  "size:S|b0bec5|50-200 LOC / 2-5 files"
  "size:M|607d8b|200-400 LOC / 5-10 files"
  "size:L|455a64|400-500 LOC / up to 10 files (ceiling — split if bigger)"
)

created=0
existed=0
failed_entries=()

for entry in "${LABELS[@]}"; do
  name="${entry%%|*}"
  rest="${entry#*|}"
  color="${rest%%|*}"
  desc="${rest#*|}"

  # Capture stderr to distinguish "already exists" from real errors.
  set +e
  err="$(gh label create "$name" --color "$color" --description "$desc" 2>&1 >/dev/null)"
  rc=$?
  set -e

  if [ "$rc" -eq 0 ]; then
    created=$((created + 1))
    printf '  + %s\n' "$name"
  elif printf '%s' "$err" | grep -qiE 'already exists'; then
    existed=$((existed + 1))
  else
    failed_entries+=("${name}: ${err}")
  fi
done

printf '   created: %d  already existed: %d  failed: %d\n' \
  "$created" "$existed" "${#failed_entries[@]}"

if [ "${#failed_entries[@]}" -gt 0 ]; then
  {
    printf '%s: error: label creation failed for:\n' "$BSP_SCRIPT_NAME"
    for f in "${failed_entries[@]}"; do
      printf '    - %s\n' "$f"
    done
    printf '   aborting; fix token scope or label conflicts, then retry.\n'
  } >&2
  exit 1
fi

# ---- Step 2: project validation -----------------------------------------
printf '→ validating project %s...\n' "$PROJECT"

# Only capture stderr; we don't need the JSON body, just to know it resolved.
if ! VIEW_ERR="$(gh project view "$NUMBER" --owner "$OWNER" --format json 2>&1 >/dev/null)"; then
  {
    printf '%s: error: project %s not accessible:\n' "$BSP_SCRIPT_NAME" "$PROJECT"
    printf '    %s\n' "$VIEW_ERR"
    printf '  Check: project exists; gh token has `project` scope; OWNER (user vs org) is correct.\n'
  } >&2
  exit 1
fi

if ! FIELD_JSON="$(gh project field-list "$NUMBER" --owner "$OWNER" --format json 2>&1)"; then
  bsp_die "cannot list project fields: $FIELD_JSON" 1
fi

if ! EXISTING_STATUSES="$(
  printf '%s' "$FIELD_JSON" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception as e:
    print("json parse error:", e, file=sys.stderr)
    sys.exit(2)
for f in d.get("fields", []):
    if f.get("name") == "Status":
        for o in f.get("options", []):
            print(o.get("name", ""))
        break
'
)"; then
  bsp_die "failed to parse project fields JSON" 1
fi

REQUIRED_STATUSES=("Backlog" "Ready" "In Progress" "In Review" "Done" "Blocked")

if [ -z "$EXISTING_STATUSES" ]; then
  {
    printf '%s: error: project has no Status field (or no options on it).\n' "$BSP_SCRIPT_NAME"
    printf '  Open the project in GitHub UI, add a single-select field named "Status" with:\n'
    for s in "${REQUIRED_STATUSES[@]}"; do printf '    • %s\n' "$s"; done
  } >&2
  exit 1
fi

MISSING_STATUSES=()
for want in "${REQUIRED_STATUSES[@]}"; do
  if ! printf '%s\n' "$EXISTING_STATUSES" | grep -Fxq "$want"; then
    MISSING_STATUSES+=("$want")
  fi
done

if [ "${#MISSING_STATUSES[@]}" -gt 0 ]; then
  {
    printf '%s: error: project Status field is missing options:\n' "$BSP_SCRIPT_NAME"
    for s in "${MISSING_STATUSES[@]}"; do printf '    • %s\n' "$s"; done
    printf '  Add them via the GitHub Project UI (Project v2 does not allow creating\n'
    printf '  single-select options via the API with a standard token). Then re-run.\n'
  } >&2
  exit 1
fi

printf '   ✓ Status field has all %d required options\n' "${#REQUIRED_STATUSES[@]}"

# ---- Step 3: config file ------------------------------------------------
printf '→ writing .board-superpowers/config.yml...\n'
mkdir -p .board-superpowers \
  || bsp_die "failed to create .board-superpowers/" 1

# Values are already validated as OWNER/NUMBER + positive integer, but we
# still quote the string scalar — defense in depth + makes diff-friendly
# edits obvious.
{
  printf '# board-superpowers project config.\n'
  printf '# Managed by using-board-superpowers. Safe to edit by hand.\n'
  printf '\n'
  printf 'project: "%s"\n' "$PROJECT"
  printf 'wip_limit: %s\n' "$WIP"
  printf '\n'
  printf '# Future fields (not yet consumed):\n'
  printf '#   base_branch: main\n'
  printf '#   default_execution_skill: superpowers:subagent-driven-development\n'
} > .board-superpowers/config.yml \
  || bsp_die "failed to write .board-superpowers/config.yml" 1
printf '   ✓ written\n'

# ---- Step 4: .gitignore --------------------------------------------------
printf '→ updating .gitignore...\n'
ENTRY='.board-superpowers/claims/'

append_gitignore() {
  {
    printf '# board-superpowers local state (claim markers are per-session)\n'
    printf '%s\n' "$ENTRY"
  } >> .gitignore
}

if [ -f .gitignore ]; then
  if grep -Fxq "$ENTRY" .gitignore; then
    printf '   ✓ already present\n'
  else
    # Ensure the existing file ends with a newline before appending.
    if [ -s .gitignore ] && [ "$(tail -c 1 .gitignore | wc -l | tr -d ' ')" = "0" ]; then
      printf '\n' >> .gitignore
    fi
    # Prefix a blank line to visually separate our block.
    printf '\n' >> .gitignore
    append_gitignore
    printf '   ✓ appended\n'
  fi
else
  append_gitignore
  printf '   ✓ created\n'
fi

# ---- done ---------------------------------------------------------------
cat <<EOF

✅ bootstrap complete for ${PROJECT}

next steps:
  1. commit: git add .board-superpowers/ .gitignore && \\
             git commit -m "chore: bootstrap board-superpowers"
  2. use-board-superpowers skill will now offer to inject routing
     rules into CLAUDE.md.
  3. tell the architect: "ready. open a Manager session and say
     'what should I work on today'."
EOF
