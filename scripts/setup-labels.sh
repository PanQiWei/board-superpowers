#!/usr/bin/env bash
# scripts/setup-labels.sh — create the 13 standard board-superpowers labels
# (4 ops + 9 type+size).
#
# Run once per repo after installing the plugin. Idempotent — labels that
# already exist are skipped (detected via `gh label list`).
#
# Why this exists: GitHub labels are a per-repo resource that the plugin
# can't auto-create at install time (no plugin-level setup hook on either
# CC or Codex). This script does the one-shot create.
#
# Standard labels (per docs/architecture/0005-contracts/05-github-artifact-schemas.md
# § "Standard label set"):
#
#   Ops (4):
#     wip-override          — claim past WIP cap (Producer-applied)
#     suspended             — card paused mid-work, still counts toward WIP
#     security              — triggers gstack:/cso review on PR submit
#     pr-contract-override  — bypass three-section validation on PR
#
#   Type (5):
#     type:feature          — A new user-visible capability
#     type:bug              — A defect in existing behavior
#     type:chore            — Non-code or infra work (deps, rename, config)
#     type:refactor         — Internal restructuring with no behavior change
#     type:epic             — A container for several vertical-slice cards
#
#   Size (4):
#     size:XS               — Under 50 LOC / 1-2 files
#     size:S                — 50-200 LOC / 2-5 files
#     size:M                — 200-400 LOC / 5-10 files
#     size:L                — 400-500 LOC / up to 10 files (ceiling)
#
# Rate-limit note: a 100ms sleep follows each successful create call to
# defend against GitHub's secondary-rate-limit on cold-start when all 13
# labels need creating in a row. Skipped labels (already present) do NOT
# pause — only created ones do.
#
# Usage:
#   bash scripts/setup-labels.sh                    # in current repo
#   bash scripts/setup-labels.sh --repo owner/name  # in named repo

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

REPO_ARG=""
if [ "${1:-}" = "--repo" ]; then
    REPO_ARG="--repo $2"
    shift 2
fi

bsp_require_cmd gh

create_label() {
    local name="$1"
    local color="$2"
    local description="$3"
    # shellcheck disable=SC2086  # REPO_ARG intentionally unquoted for splitting
    if gh label list ${REPO_ARG} --json name 2>/dev/null \
        | python3 -c "import json,sys; print('\n'.join(l['name'] for l in json.load(sys.stdin)))" \
        | grep -Fx "${name}" >/dev/null 2>&1; then
        bsp_log "label '${name}' already exists — skipping"
    else
        # shellcheck disable=SC2086  # REPO_ARG intentionally unquoted for splitting
        gh label create "${name}" --color "${color}" --description "${description}" ${REPO_ARG}
        bsp_log "created label '${name}'"
        # Defend against GitHub secondary-rate-limit on cold-start when all
        # 13 labels need creating back-to-back. 100ms is the conservative
        # floor; only the create path pauses (skips do not).
        sleep 0.1
    fi
}

# Ops labels (4) — preserved from v0.1.0-minimum, untouched.
create_label "wip-override"         "FBCA04" "Allows Consumer to claim past WIP cap"
create_label "suspended"            "D4C5F9" "Card paused mid-work; still counts toward WIP"
create_label "security"             "B60205" "Triggers gstack:/cso security review on PR submit"
create_label "pr-contract-override" "C5DEF5" "Bypass PR three-section validation"

# Type labels (5) — per spec table § "Type labels".
create_label "type:feature"         "0e8a16" "A new user-visible capability"
create_label "type:bug"             "d73a4a" "A defect in existing behavior"
create_label "type:chore"           "c5def5" "Non-code or infra work (deps, rename, config)"
create_label "type:refactor"        "fbca04" "Internal restructuring with no behavior change"
create_label "type:epic"            "5319e7" "A container for several vertical-slice cards"

# Size labels (4) — per spec table § "Size labels".
create_label "size:XS"              "cccccc" "Under 50 LOC / 1-2 files"
create_label "size:S"               "b0bec5" "50-200 LOC / 2-5 files"
create_label "size:M"               "607d8b" "200-400 LOC / 5-10 files"
create_label "size:L"               "455a64" "400-500 LOC / up to 10 files (ceiling — split if bigger)"

bsp_log "done — 13 standard labels are present"
