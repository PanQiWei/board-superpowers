#!/usr/bin/env bash
# tests/test-bootstrapping-repo-skill.sh — assert the
# skills/bootstrapping-repo/ molecular skill ships with a complete,
# spec-conformant set of files: SKILL.md frontmatter + body, the three
# reference files (intro, first-time-user-guide, changelog/v0.2.0),
# and a valid .skill-meta.yaml.
#
# This is a content / contract check on the skill directory (the SKILL
# is consumed by the model at runtime — no executable to drive).
# Pragmatic grep-based assertions cover the load-bearing claims.
#
# Spec under test:
#   docs/architecture/0002-product-features-and-flows/05-bootstrap-surface.md
#     § 1.5.1 F-B1 + § 1.5.2 F-B2 (the orchestrated procedures)
#   SKILL_DEVELOPMENT.md § "Three-tier frontmatter discipline"
#     (no Tier 3 fields; Tier 1 + Tier 2 only)
#   SKILLS.md § "bootstrapping-repo" catalog row
#     (must mention the skill in a #### heading for verify-skill-metadata)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT_REAL="$(cd "${SCRIPT_DIR}/.." && pwd)"
SKILL_DIR="${PLUGIN_ROOT_REAL}/skills/bootstrapping-repo"
SKILL_FILE="${SKILL_DIR}/SKILL.md"
META_FILE="${SKILL_DIR}/.skill-meta.yaml"
INTRO_FILE="${SKILL_DIR}/references/intro.md"
GUIDE_FILE="${SKILL_DIR}/references/first-time-user-guide.md"
CHANGELOG_FILE="${SKILL_DIR}/references/changelog/v0.2.0.md"

if [ ! -d "${SKILL_DIR}" ]; then
    printf 'FATAL: %s not found\n' "${SKILL_DIR}" >&2
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
# 1. File presence
# ---------------------------------------------------------------------------
printf 'File presence\n'

check 'SKILL.md exists' \
    test -f "${SKILL_FILE}"
check '.skill-meta.yaml exists' \
    test -f "${META_FILE}"
check 'references/intro.md exists' \
    test -f "${INTRO_FILE}"
check 'references/first-time-user-guide.md exists' \
    test -f "${GUIDE_FILE}"
check 'references/changelog/v0.2.0.md exists' \
    test -f "${CHANGELOG_FILE}"

# Bail out early if SKILL.md or .skill-meta.yaml is missing — the
# remaining checks would just produce noise.
if [ ! -f "${SKILL_FILE}" ] || [ ! -f "${META_FILE}" ]; then
    printf '\nResults: %d passed, %d failed (early bail — required files missing)\n' \
        "${PASS}" "${FAIL}"
    exit 1
fi

# ---------------------------------------------------------------------------
# 2. Frontmatter — Tier 1 portable subset (name + description) + Tier 2
#    (when_to_use). NO Tier 3 fields.
# ---------------------------------------------------------------------------
printf 'Frontmatter discipline\n'

check 'frontmatter has name: bootstrapping-repo' \
    grep -qE '^name: bootstrapping-repo$' "${SKILL_FILE}"
check 'frontmatter has description (Tier 1)' \
    grep -qE '^description: ' "${SKILL_FILE}"
check 'frontmatter has when_to_use (Tier 2)' \
    grep -qE '^when_to_use: ' "${SKILL_FILE}"

# Anti-pattern A4: NO Tier 3 fields. The CC spec set is in
# verify-skill-frontmatter.sh; here we just assert the four most-common
# project-metadata leaks are NOT in the frontmatter (they belong in
# .skill-meta.yaml, not SKILL.md).
check 'frontmatter does NOT contain version: (Tier 3 leak guard)' \
    bash -c "! awk '/^---\$/{c++; next} c==1{print}' '${SKILL_FILE}' | grep -qE '^version:'"
check 'frontmatter does NOT contain layer: (Tier 3 leak guard)' \
    bash -c "! awk '/^---\$/{c++; next} c==1{print}' '${SKILL_FILE}' | grep -qE '^layer:'"
check 'frontmatter does NOT contain type: (Tier 3 leak guard)' \
    bash -c "! awk '/^---\$/{c++; next} c==1{print}' '${SKILL_FILE}' | grep -qE '^type:'"
check 'frontmatter does NOT contain bounded-context: (Tier 3 leak guard)' \
    bash -c "! awk '/^---\$/{c++; next} c==1{print}' '${SKILL_FILE}' | grep -qE '^bounded-context:'"

# ---------------------------------------------------------------------------
# 3. .skill-meta.yaml — five required fields with valid enum values.
# ---------------------------------------------------------------------------
printf '.skill-meta.yaml schema\n'

check 'meta has version' \
    grep -qE '^version: ' "${META_FILE}"
check 'meta version is semver-shaped' \
    grep -qE '^version: v?[0-9]+\.[0-9]+\.[0-9]+' "${META_FILE}"
check 'meta has layer: molecular' \
    grep -qE '^layer: molecular$' "${META_FILE}"
check 'meta has type (one of pattern/technique/reference/discipline)' \
    grep -qE '^type: (pattern|technique|reference|discipline)$' "${META_FILE}"
check 'meta has mode: both' \
    grep -qE '^mode: both$' "${META_FILE}"
check 'meta has bounded-context: bootstrap' \
    grep -qE '^bounded-context: bootstrap$' "${META_FILE}"

# ---------------------------------------------------------------------------
# 4. Body — load-bearing procedures (F-B1, F-B2, action ID catalog,
#    R-class, audit log, idempotency).
# ---------------------------------------------------------------------------
printf 'Body — load-bearing procedures\n'

check 'body describes host bootstrap step' \
    grep -qiE '^### Step 1 — host bootstrap|host bootstrap' "${SKILL_FILE}"
check 'body describes per-repo bootstrap step' \
    grep -qiE 'per-repo bootstrap|^### Step 3' "${SKILL_FILE}"
check 'body invokes bootstrap-host.sh script' \
    grep -q 'bootstrap-host\.sh' "${SKILL_FILE}"
check 'body invokes bootstrap-project.sh script' \
    grep -q 'bootstrap-project\.sh' "${SKILL_FILE}"
check 'body references the 7 bootstrap-project sub-steps (2a..2g)' \
    bash -c "grep -qE '2a.*labels' '${SKILL_FILE}' && \
             grep -qE '2b.*Status' '${SKILL_FILE}' && \
             grep -qE '2c.*config' '${SKILL_FILE}' && \
             grep -qE '2d.*\\.gitignore' '${SKILL_FILE}' && \
             grep -qE '2e.*credential' '${SKILL_FILE}' && \
             grep -qE '2f.*venv|2f.*uv sync' '${SKILL_FILE}' && \
             grep -qE '2g.*audit-init|2g.*DDL' '${SKILL_FILE}'"
check 'body references step 4 routing injection' \
    grep -qE 'routing.*inject|step 4.*routing' "${SKILL_FILE}"
check 'body mentions CLAUDE.md AND AGENTS.md as routing targets' \
    bash -c "grep -q 'CLAUDE\\.md' '${SKILL_FILE}' && grep -q 'AGENTS\\.md' '${SKILL_FILE}'"
check 'body mentions state.yml host-local path' \
    grep -qE 'state\.yml' "${SKILL_FILE}"

printf 'Body — action catalog\n'

check 'body contains action ID catalog block' \
    grep -qE 'Bootstrap actions:|action_id catalog|Action ID catalog' "${SKILL_FILE}"
check 'catalog names bootstrap-host action' \
    grep -q 'bootstrap-host' "${SKILL_FILE}"
check 'catalog names bootstrap-project-2a..2e actions' \
    bash -c "grep -q 'bootstrap-project-2a' '${SKILL_FILE}' && grep -q 'bootstrap-project-2e' '${SKILL_FILE}'"
check 'catalog names bootstrap-project-4 routing action' \
    grep -q 'bootstrap-project-4' "${SKILL_FILE}"

printf 'Body — governance via atomic skills\n'

check 'body declares the R-class posture (mostly R-class)' \
    grep -qE 'mostly R-class|Why bootstrap is mostly R-class' "${SKILL_FILE}"
check 'body invokes board-superpowers:classifying-actions' \
    grep -q 'board-superpowers:classifying-actions' "${SKILL_FILE}"
check 'body invokes board-superpowers:auditing-actions' \
    grep -q 'board-superpowers:auditing-actions' "${SKILL_FILE}"
check 'body documents the 5-step governance sequence' \
    grep -qiE '5-step.*governance|How mutating actions are handled' "${SKILL_FILE}"

printf 'Body — idempotency + failure paths\n'

check 'body asserts re-running is a no-op on bootstrapped repo' \
    grep -qiE 'idempot|no-op|already.*bootstrapped' "${SKILL_FILE}"
check 'body documents --force escape hatch' \
    grep -qE -- '--force' "${SKILL_FILE}"
check 'body has a failure-paths section' \
    grep -qiE '^## Failure paths|## Failure path' "${SKILL_FILE}"
check 'body documents Status field drift recovery (exit 2)' \
    grep -qE 'exit 2|Status.*drift' "${SKILL_FILE}"

printf 'Body — anti-pattern guard\n'

check 'body has anti-pattern: bootstrapping without consent' \
    grep -qiE 'anti-pattern.*consent|without consent|never run.*silently|MUST NOT.*silent' "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# 5. References — content sanity checks.
# ---------------------------------------------------------------------------
printf 'References — intro.md\n'

check 'intro.md mentions two-role mental model' \
    grep -qiE 'two-role|Producer.*Consumer|Manager.*Implementer' "${INTRO_FILE}"
check 'intro.md mentions superpowers + gstack composition' \
    bash -c "grep -q 'superpowers' '${INTRO_FILE}' && grep -q 'gstack' '${INTRO_FILE}'"
check 'intro.md addresses BYO-RDBMS opt-out question' \
    grep -qiE 'opt[- ]out|do I need.*postgres|byo-rdbms.*decline' "${INTRO_FILE}"

printf 'References — first-time-user-guide.md\n'

check 'guide.md mentions Manager session intake path' \
    grep -qE 'managing-board|intake routine' "${GUIDE_FILE}"
check 'guide.md mentions GitHub UI card-paste path' \
    grep -qiE 'paste.*card|paste.*github|github UI.*card' "${GUIDE_FILE}"
check 'guide.md documents [board-card:#N] claim trigger' \
    grep -qE '\[board-card:#N\]' "${GUIDE_FILE}"
check 'guide.md lists state file paths' \
    bash -c "grep -q 'manifest\\.yml' '${GUIDE_FILE}' && grep -q 'state\\.yml' '${GUIDE_FILE}' && grep -q 'config\\.yml' '${GUIDE_FILE}'"

printf 'References — changelog/v0.2.0.md\n'

check "changelog has \"What's new for the host\" section" \
    grep -qiE "What'?s new for the host" "${CHANGELOG_FILE}"
check "changelog has \"What's new ... every repo\" section" \
    grep -qiE "What'?s new.*every repo|affects every repo" "${CHANGELOG_FILE}"
check 'changelog has breaking-changes section' \
    grep -qiE 'Breaking changes' "${CHANGELOG_FILE}"
check 'changelog mentions migration from v0.1.1' \
    grep -qE 'v0\.1\.1|0\.1\.1' "${CHANGELOG_FILE}"
check 'changelog references F-B4 hash-recording' \
    grep -qE 'F-B4|hash.*record|block_hash' "${CHANGELOG_FILE}"

# ---------------------------------------------------------------------------
# 6. SKILLS.md catalog mention (required by verify-skill-metadata.sh).
# ---------------------------------------------------------------------------
printf 'SKILLS.md catalog\n'

SKILLS_MD="${PLUGIN_ROOT_REAL}/SKILLS.md"
# shellcheck disable=SC2016 # backticks are markdown literals here, not command substitution
check 'SKILLS.md mentions bootstrapping-repo as a #### heading' \
    grep -qE '^#### `bootstrapping-repo`' "${SKILLS_MD}"

# ---------------------------------------------------------------------------
# 7. Body length budget — molecular = 250-450 lines target. We let the
#    actual body bracket the looser practiced range (~150-450) since
#    other v1-minimum molecular skills (managing-board, consuming-card)
#    landed under 250 too. Just guard against absurdly short / long.
# ---------------------------------------------------------------------------
printf 'Body length sanity\n'

LINES="$(wc -l < "${SKILL_FILE}" | tr -d ' ')"
check 'SKILL.md has at least 100 lines (molecular floor)' \
    test "${LINES}" -ge 100
check 'SKILL.md has at most 500 lines (molecular ceiling)' \
    test "${LINES}" -le 500

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\nResults: %d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" = "0" ]
