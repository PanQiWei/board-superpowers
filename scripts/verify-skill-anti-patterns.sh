#!/usr/bin/env bash
# scripts/verify-skill-anti-patterns.sh — CI gate for SKILL_DEVELOPMENT.md
# anti-patterns A9 (internal codes / cross-boundary refs) + A10 (phase
# narrative).
#
# Resolves the plugin root via SCRIPT_DIR rather than bsp_primary_repo_root.
# bsp_primary_repo_root follows .git/common-dir, which from a worktree
# resolves to the main repo's working tree — wrong for a CI gate that
# wants to scan the *current* working tree's SKILL files. Using SCRIPT_DIR
# scans whichever copy of the plugin the script is invoked from (main,
# worktree, or downstream test harness).
#
# Test override: BSP_TEST_PLUGIN_ROOT, when set to an absolute directory,
# replaces SCRIPT_DIR-derived PLUGIN_ROOT for the scope of this run. Used
# by tests/test-verify-skill-anti-patterns.sh to scan a fixture tree
# instead of the live skills/ tree. Production callers MUST NOT set it.
#
# Exit 0: clean.
# Exit 1: violations found (printed to stderr).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
# shellcheck source-path=SCRIPTDIR
source "${SCRIPT_DIR}/lib/common.sh"

if [ -n "${BSP_TEST_PLUGIN_ROOT:-}" ] && [ -d "${BSP_TEST_PLUGIN_ROOT}" ]; then
    PLUGIN_ROOT="${BSP_TEST_PLUGIN_ROOT}"
else
    PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi
SKILLS_DIR="${PLUGIN_ROOT}/skills"
[ -d "${SKILLS_DIR}" ] || bsp_die "skills/ directory not found at ${SKILLS_DIR}"

ERRORS=0

# A9: internal codes + cross-boundary refs.
#
# Scope: skills/**/SKILL.md AND skills/**/references/**.md.
# Audit on PR #70 found ~85+ dead-link refs lived in references/**.md
# files that the previous SKILL.md-only scan never touched. References
# files ship alongside SKILL.md as plugin payload, so a downstream agent
# loading them suffers the same "indecipherable internal code" failure
# as A9 originally documented for SKILL.md.
#
# Patterns:
#   - Existing internal-code family (F-XX, ADR-XXXX, §X., PXa, I-X,
#     D-XXX-X, C-XXX-X) — unchanged from prior gate.
#   - docs/architecture/ literal substring — covers absolute-from-repo-
#     root paths and embedded markdown links.
#   - ../../docs/ — relative-path traversal that escapes the plugin
#     install boundary.
#   - Root maintainer-doc filenames (BOARD_DEVELOPMENT.md /
#     MULTI_AGENT_DEVELOPMENT.md / SKILL_DEVELOPMENT.md /
#     PLUGIN_DEVELOPMENT.md / SETUP_STAGES_DEVELOPMENT.md) — these live
#     at the repo root and do NOT ship with `plugin install`.
#   - adr/0[0-9]{3} relative-path fragment — ADR file paths in the
#     spec tree.
#
# Exclusions:
#   - skills/AGENTS.md — maintainer-side contract for plugin authors,
#     not a SKILL reference. Legitimately points up into ../docs/ etc.
#   - Lines containing the literal "not shipped with plugin install"
#     marker — the B5 escape hatch for high-value canonical-spec
#     pointers in references/ that explicitly disclaim themselves as
#     maintainer-only context (see SKILL_DEVELOPMENT.md § A9 footnote
#     pattern). The marker MUST appear on the same physical line as
#     the cross-boundary reference for the line to be excluded.
A9_PATTERN='\bF-[A-Z]?[0-9]+|ADR-[0-9]{4}|§[0-9]\.|P[0-9]+[a-z]?\b|I-[0-9]+|D-[A-Z]+-[0-9]+|C-[A-Z]+-[0-9]+|docs/architecture/|\.\./\.\./docs/|BOARD_DEVELOPMENT\.md|MULTI_AGENT_DEVELOPMENT\.md|SKILL_DEVELOPMENT\.md|PLUGIN_DEVELOPMENT\.md|SETUP_STAGES_DEVELOPMENT\.md|adr/0[0-9]{3}'

A9_INPUT="$(mktemp)"
A9_TMP_TRAP="rm -f \"${A9_INPUT}\""

# 1) SKILL.md scan — every skills/**/SKILL.md.
grep -rnE "${A9_PATTERN}" "${SKILLS_DIR}" --include='SKILL.md' 2>/dev/null \
    >> "${A9_INPUT}" || true

# 2) references/**.md scan — every skills/**/references/**.md, EXCLUDING
# skills/AGENTS.md (which is at skills/ root, not under references/).
# We use find + xargs so we only touch references/ subtrees.
while IFS= read -r ref_file; do
    grep -nE "${A9_PATTERN}" "${ref_file}" 2>/dev/null \
        | sed "s|^|${ref_file}:|" >> "${A9_INPUT}" || true
done < <(find "${SKILLS_DIR}" -type f -name '*.md' -path '*/references/*')

while IFS= read -r match; do
    [ -z "${match}" ] && continue
    # B5 escape hatch — same-line "not shipped with plugin install"
    # marker indicates a deliberate, scoped maintainer-pointer.
    if printf '%s' "${match}" | grep -q 'not shipped with plugin install'; then
        continue
    fi
    # Extract path:line and the matched substring for the human-
    # readable diagnostic. Match-substring extraction uses the same
    # ERE the scan ran with.
    file_line="$(printf '%s' "${match}" | cut -d: -f1-2)"
    matched="$(printf '%s' "${match}" | grep -oE "${A9_PATTERN}" | head -1)"
    # Strip the absolute PLUGIN_ROOT prefix so output is repo-relative.
    rel_file_line="${file_line#"${PLUGIN_ROOT}/"}"
    bsp_warn "A9 violation: ${rel_file_line}: ${matched}"
    bsp_warn "  → translate the reference to self-contained prose; see SKILL_DEVELOPMENT.md § A9 for examples."
    ERRORS=$((ERRORS + 1))
done < "${A9_INPUT}"

eval "${A9_TMP_TRAP}"
unset A9_TMP_TRAP

# A10: phase narrative across SKILL files AND root-level developer-
# facing docs (AGENTS.md, plugin manifests longDescription, etc.) where
# stale "v1-minimum" framing has historically leaked. Whitelist is path-
# specific (NOT glob — the previous `skills/*/references/changelog/*.md`
# glob would have whitelisted any future skill's changelog file by
# accident, which is a real bypass surface).
A10_PATTERN='v[0-9]+-(minimum|complete)|deferred to|degradation block|degraded mode'
WHITELIST_FILES=(
    "skills/auditing-actions/references/degradation-mode.md"
    "skills/bootstrapping-repo/references/changelog/v0.2.0.md"
)
A10_TARGETS=(
    "${SKILLS_DIR}"
    "${PLUGIN_ROOT}/AGENTS.md"
    "${PLUGIN_ROOT}/CLAUDE.md"
    "${PLUGIN_ROOT}/SKILLS.md"
    "${PLUGIN_ROOT}/.claude-plugin/plugin.json"
    "${PLUGIN_ROOT}/.codex-plugin/plugin.json"
)
A10_INPUT="$(mktemp)"
trap 'rm -f "${A10_INPUT}"' EXIT
for tgt in "${A10_TARGETS[@]}"; do
    if [ -d "${tgt}" ]; then
        grep -rnE "${A10_PATTERN}" "${tgt}" --include='*.md' --include='*.json' 2>/dev/null >> "${A10_INPUT}" || true
    elif [ -f "${tgt}" ]; then
        grep -nE "${A10_PATTERN}" "${tgt}" 2>/dev/null | sed "s|^|${tgt}:|" >> "${A10_INPUT}" || true
    fi
done
while read -r match; do
    [ -z "${match}" ] && continue
    file="$(printf '%s' "${match}" | cut -d: -f1)"
    rel_file="${file#"${PLUGIN_ROOT}/"}"
    skip=0
    for w in "${WHITELIST_FILES[@]}"; do
        [ "${rel_file}" = "${w}" ] && { skip=1; break; }
    done
    # SKILLS.md catalog rows describe roadmap items — "deferred to v1-
    # complete" is legitimate roadmap phrasing for the 2 unshipped
    # skills. Whitelist this file as a whole.
    [ "${rel_file}" = "SKILLS.md" ] && skip=1
    [ "${skip}" = 1 ] && continue
    bsp_warn "A10 violation: ${match}"
    ERRORS=$((ERRORS + 1))
done < "${A10_INPUT}"

if [ "${ERRORS}" -gt 0 ]; then
    bsp_warn "${ERRORS} anti-pattern violation(s) found"
    exit 1
fi

bsp_log "anti-pattern grep clean (A9 + A10)"
exit 0
