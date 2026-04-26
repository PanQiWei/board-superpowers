#!/usr/bin/env bash
# scripts/setup-labels.sh — create the 4 standard board-superpowers labels.
#
# Run once per repo after installing the plugin. Idempotent — labels that
# already exist are skipped (gh prints a warning).
#
# Why this exists: GitHub labels are a per-repo resource that the plugin
# can't auto-create at install time (no plugin-level setup hook on either
# CC or Codex). This script does the one-shot create.
#
# Standard labels:
#   wip-override          — claim past WIP cap (Producer-applied)
#   suspended             — card paused mid-work, still counts toward WIP
#   security              — triggers gstack:/cso review on PR submit
#   pr-contract-override  — bypass three-section validation on PR
#
# Usage:
#   bash scripts/setup-labels.sh                    # in current repo
#   bash scripts/setup-labels.sh --repo owner/name  # in named repo

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
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
    if gh label list ${REPO_ARG} --json name 2>/dev/null \
        | python3 -c "import json,sys; print('\n'.join(l['name'] for l in json.load(sys.stdin)))" \
        | grep -Fx "${name}" >/dev/null 2>&1; then
        bsp_log "label '${name}' already exists — skipping"
    else
        # shellcheck disable=SC2086  # REPO_ARG intentionally unquoted for splitting
        gh label create "${name}" --color "${color}" --description "${description}" ${REPO_ARG}
        bsp_log "created label '${name}'"
    fi
}

create_label "wip-override"         "FBCA04" "Allows Consumer to claim past WIP cap"
create_label "suspended"            "D4C5F9" "Card paused mid-work; still counts toward WIP"
create_label "security"             "B60205" "Triggers gstack:/cso security review on PR submit"
create_label "pr-contract-override" "C5DEF5" "Bypass PR three-section validation"

bsp_log "done — 4 standard labels are present"
