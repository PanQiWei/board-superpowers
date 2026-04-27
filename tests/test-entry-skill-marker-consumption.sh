#!/usr/bin/env bash
# tests/test-entry-skill-marker-consumption.sh — assert
# skills/using-board-superpowers/SKILL.md consumes the
# INVOKE: bootstrapping-repo marker, references the F-B1 / F-B2
# scripts and skill names, and preserves the post-bootstrap routing
# table.
#
# This is a content / contract check on a Markdown file (the SKILL
# is consumed by the model at runtime — no executable to drive).
# Pragmatic grep-based assertions cover the load-bearing claims.
#
# Spec under test:
#   docs/architecture/0005-contracts/02-hook-contracts.md § "Intent-injection markers"
#     (Step 2 — entry skill consumes the marker)
#   docs/architecture/0002-product-features-and-flows/05-bootstrap-surface.md
#     § "three-layer alert + intent-injection strategy" (Layer 2)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT_REAL="$(cd "${SCRIPT_DIR}/.." && pwd)"
SKILL_FILE="${PLUGIN_ROOT_REAL}/skills/using-board-superpowers/SKILL.md"

if [ ! -f "${SKILL_FILE}" ]; then
    printf 'FATAL: %s not found\n' "${SKILL_FILE}" >&2
    exit 99
fi

PASS=0
FAIL=0

check() {
    local label="$1"; shift
    if "$@"; then
        printf '  PASS — %s\n' "${label}"
        PASS=$((PASS + 1))
    else
        printf '  FAIL — %s\n' "${label}" >&2
        FAIL=$((FAIL + 1))
    fi
}

# ---------------------------------------------------------------------------
# Step 1 contract: re-runs check-deps.sh in --machine mode and probes
# the host + per-repo state files.
# ---------------------------------------------------------------------------
printf 'Step 1 — Layer 2 reliable gate references\n'

check 'mentions check-deps.sh in --machine mode' \
    grep -qE 'check-deps\.sh.*--machine' "${SKILL_FILE}"
check 'mentions MISSING= key' \
    grep -qE 'MISSING=' "${SKILL_FILE}"
check 'mentions ROUTING_INJECTED= key' \
    grep -qE 'ROUTING_INJECTED=' "${SKILL_FILE}"
check 'mentions manifest.yml as a probed state file' \
    grep -q 'manifest\.yml' "${SKILL_FILE}"
check 'mentions per-repo state.yml as a probed state file' \
    grep -q 'state\.yml' "${SKILL_FILE}"
check 'mentions normalized path layout' \
    grep -qE 'repos/<normalized>' "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# Step 2 contract: consume INVOKE: bootstrapping-repo marker.
# ---------------------------------------------------------------------------
printf 'Step 2 — INVOKE marker consumption\n'

check 'mentions INVOKE: marker grammar' \
    grep -q 'INVOKE: bootstrapping-repo' "${SKILL_FILE}"
check 'mentions REASON: line' \
    grep -qE 'REASON:' "${SKILL_FILE}"
check 'declares Layer 2 reliable-gate semantics (does not depend on hook)' \
    grep -qiE 'reliable.*gate|reliability|do NOT depend on the hook|layer 2' "${SKILL_FILE}"
check 'handles unrecognized skill name in marker' \
    grep -qiE 'unrecognized.*hook intent|unknown skill' "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# Step 3 contract: chain F-B1 → F-B2.
# ---------------------------------------------------------------------------
printf 'Step 3 — F-B1 / F-B2 chain references\n'

check 'invokes bootstrap-host.sh for F-B1' \
    grep -q 'bootstrap-host\.sh' "${SKILL_FILE}"
check 'mentions bootstrapping-repo skill for F-B2' \
    grep -q 'bootstrapping-repo' "${SKILL_FILE}"
check 'mentions bootstrap-project.sh as F-B2 driver' \
    grep -q 'bootstrap-project\.sh' "${SKILL_FILE}"
check 'declares F-B1 → F-B2 chain order' \
    grep -qiE 'F-B1.*F-B2|F-B1 first|chain.*F-B2|then chain' "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# Post-bootstrap routing table preserved.
# ---------------------------------------------------------------------------
printf 'Post-bootstrap routing table preserved\n'

check 'preserves [board-card:#N] routing to consuming-card' \
    grep -qE '\[board-card:#N\].*consuming-card' "${SKILL_FILE}"
check 'preserves "claim card" routing to consuming-card' \
    grep -qE 'claim card N.*consuming-card' "${SKILL_FILE}"
check 'preserves morning briefing → managing-board (daily)' \
    grep -qE 'morning briefing.*managing-board' "${SKILL_FILE}"
check 'preserves review-the-PRs → managing-board (review-queue)' \
    grep -qE 'review the PRs.*managing-board' "${SKILL_FILE}"
check 'preserves intake routing → managing-board' \
    grep -qE 'new requirement.*managing-board|intake.*managing-board' "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# Frontmatter contract — name + description + when_to_use unchanged
# ---------------------------------------------------------------------------
printf 'Frontmatter integrity\n'

check 'frontmatter has name: using-board-superpowers' \
    grep -qE '^name: using-board-superpowers$' "${SKILL_FILE}"
check 'frontmatter has description' \
    grep -qE '^description: ' "${SKILL_FILE}"
check 'frontmatter mentions INVOKE marker via when_to_use' \
    grep -qE '^when_to_use: .*INVOKE' "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# Self-containment / anti-pattern guard
# ---------------------------------------------------------------------------
printf 'Anti-pattern guards\n'

check 'preserves anti-pattern: routing that becomes work' \
    grep -qiE 'routing that becomes work|MUST NOT do real work' "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\nResults: %d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" = "0" ]
