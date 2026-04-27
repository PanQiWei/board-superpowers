#!/usr/bin/env bash
# scripts/verify-skill-anti-patterns.sh — CI gate for SKILL_DEVELOPMENT.md
# anti-patterns A9 (internal codes) + A10 (phase narrative).
#
# Resolves the plugin root via SCRIPT_DIR rather than bsp_primary_repo_root.
# bsp_primary_repo_root follows .git/common-dir, which from a worktree
# resolves to the main repo's working tree — wrong for a CI gate that
# wants to scan the *current* working tree's SKILL files. Using SCRIPT_DIR
# scans whichever copy of the plugin the script is invoked from (main,
# worktree, or downstream test harness).
#
# Exit 0: clean.
# Exit 1: violations found (printed to stderr).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
# shellcheck source-path=SCRIPTDIR
source "${SCRIPT_DIR}/lib/common.sh"

PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SKILLS_DIR="${PLUGIN_ROOT}/skills"
[ -d "${SKILLS_DIR}" ] || bsp_die "skills/ directory not found at ${SKILLS_DIR}"

ERRORS=0

# A9: internal codes in SKILL.md (not references/).
A9_PATTERN='\bF-[A-Z]?[0-9]+|ADR-[0-9]{4}|§[0-9]\.|P[0-9]+[a-z]?\b|I-[0-9]+|D-[A-Z]+-[0-9]+|C-[A-Z]+-[0-9]+'
while read -r match; do
    [ -z "${match}" ] && continue
    bsp_warn "A9 violation: ${match}"
    ERRORS=$((ERRORS + 1))
done < <(grep -rnE "${A9_PATTERN}" "${SKILLS_DIR}" --include='SKILL.md' 2>/dev/null || true)

# A10: phase narrative across all SKILL files. Whitelist supports glob
# patterns (matched via bash case). Whitelisted by-design entries:
#   - changelog/*.md is phase-narrative by definition per
#     SKILL_DEVELOPMENT.md A10's "Phase narrative belongs in CHANGELOG"
#     fix-table footnote.
#   - degradation-mode.md carries the legacy mode-field enum value
#     `v1-minimum-degraded` documented in spec 06.
A10_PATTERN='v[0-9]+-(minimum|complete)|deferred to|degradation block|degraded mode'
WHITELIST_PATTERNS=(
    "skills/auditing-actions/references/degradation-mode.md"
    "skills/*/references/changelog/*.md"
)
while read -r match; do
    [ -z "${match}" ] && continue
    file="$(printf '%s' "${match}" | cut -d: -f1)"
    rel_file="${file#"${PLUGIN_ROOT}/"}"
    skip=0
    for w in "${WHITELIST_PATTERNS[@]}"; do
        # shellcheck disable=SC2254
        case "${rel_file}" in ${w}) skip=1; break ;; esac
    done
    [ "${skip}" = 1 ] && continue
    bsp_warn "A10 violation: ${match}"
    ERRORS=$((ERRORS + 1))
done < <(grep -rnE "${A10_PATTERN}" "${SKILLS_DIR}" --include='*.md' 2>/dev/null || true)

if [ "${ERRORS}" -gt 0 ]; then
    bsp_warn "${ERRORS} anti-pattern violation(s) found"
    exit 1
fi

bsp_log "anti-pattern grep clean (A9 + A10)"
exit 0
