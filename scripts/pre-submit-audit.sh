#!/usr/bin/env bash
# scripts/pre-submit-audit.sh — pre-PR automation aggregator.
#
# Runs all pre-PR checks in sequence; outputs Markdown to stdout
# suitable for pasting into a PR body's "## Automated Verification"
# section. Returns 0 if all checks passed; 1 otherwise.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
# shellcheck source-path=SCRIPTDIR
source "${SCRIPT_DIR}/lib/common.sh"

REPO_ROOT="$(bsp_primary_repo_root "${PWD}")"
cd "${REPO_ROOT}"

OVERALL_RC=0

# Use a temp file to accumulate the markdown output.
MD="$(mktemp)"
trap 'rm -f "${MD}"' EXIT

{
    echo '## Automated Verification'
    echo ''
} > "${MD}"

run_check() {
    local label="$1"
    local cmd="$2"
    local out
    if out=$(eval "${cmd}" 2>&1); then
        printf '✓ %s\n' "${label}" >> "${MD}"
    else
        printf '✗ %s — see logs\n' "${label}" >> "${MD}"
        printf '%s\n' "${out}" | sed 's/^/    /' >> "${MD}"
        OVERALL_RC=1
    fi
}

run_check "shellcheck -x: clean" \
    "shellcheck -x scripts/*.sh scripts/lib/*.sh hooks/*.sh"
run_check "verify-skill-metadata: yaml ↔ catalog consistent" \
    "bash scripts/verify-skill-metadata.sh"
run_check "verify-skill-frontmatter: Tier 1+2 compliant, no Tier 3" \
    "bash scripts/verify-skill-frontmatter.sh"
run_check "verify-skill-anti-patterns: A9 + A10 clean" \
    "bash scripts/verify-skill-anti-patterns.sh"

# Tests — count passes vs failures.
TEST_PASS=0
TEST_FAIL=0
TEST_SKIP=0
for t in tests/*.sh; do
    [ -f "${t}" ] || continue
    if out=$(bash "${t}" 2>&1); then
        if printf '%s' "${out}" | grep -q '^SKIP'; then
            TEST_SKIP=$((TEST_SKIP + 1))
        else
            TEST_PASS=$((TEST_PASS + 1))
        fi
    else
        TEST_FAIL=$((TEST_FAIL + 1))
    fi
done
{
    if [ ${TEST_FAIL} -eq 0 ]; then
        printf '✓ tests: %d pass, %d skipped\n' "${TEST_PASS}" "${TEST_SKIP}"
    else
        printf '✗ tests: %d pass, %d skipped, %d FAIL\n' "${TEST_PASS}" "${TEST_SKIP}" "${TEST_FAIL}"
        OVERALL_RC=1
    fi
} >> "${MD}"

# uv detection.
if command -v uv >/dev/null 2>&1; then
    UV_VER="$(uv --version 2>/dev/null | awk '{print $2}')"
    printf '✓ uv detected at %s (version %s)\n' "$(command -v uv)" "${UV_VER}" >> "${MD}"
else
    printf '✗ uv NOT detected on PATH\n' >> "${MD}"
    OVERALL_RC=1
fi

# Footer.
{
    echo ''
    printf 'Run on:    %s / bash %s / python3 %s\n' \
        "$(uname -s) $(uname -r)" \
        "${BASH_VERSION%.*}" \
        "$(python3 --version 2>/dev/null | awk '{print $2}' || echo 'unknown')"
    printf 'Run at:    %s UTC\n' "$(date -u '+%Y-%m-%d %H:%M')"
    PLUGIN_VER="$(grep '"version"' .claude-plugin/plugin.json 2>/dev/null | sed -E 's/.*"version":[[:space:]]*"([^"]+)".*/\1/' | head -1)"
    printf 'Plugin:    v%s (this PR)\n' "${PLUGIN_VER:-?}"
} >> "${MD}"

cat "${MD}"
exit ${OVERALL_RC}
