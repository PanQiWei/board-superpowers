#!/usr/bin/env bash
# tests/test-phase-2-verification.sh — Phase 2 gate verification suite.
#
# Seven checks that must all pass before advancing to Phase 3.
# Each check is independent; all run regardless of prior failures.
# Exit code: 0 if all pass, 1 if any fail.
#
# Usage: bash tests/test-phase-2-verification.sh [--repo-root <path>]
# Default repo-root is git rev-parse --show-toplevel.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel)"

PASS=0; FAIL=0

check_cmd() {
    local label="$1"; shift
    if "$@" >/dev/null 2>&1; then
        printf 'PASS  [%s]\n' "${label}"; PASS=$((PASS+1))
    else
        printf 'FAIL  [%s]\n' "${label}" >&2; FAIL=$((FAIL+1))
    fi
}

check_cmd_verbose() {
    local label="$1"; shift
    local out
    if out="$("$@" 2>&1)"; then
        printf 'PASS  [%s]\n' "${label}"; PASS=$((PASS+1))
    else
        printf 'FAIL  [%s]\n%s\n' "${label}" "${out}" >&2; FAIL=$((FAIL+1))
    fi
}

printf '=== Phase 2 verification suite ===\n\n'

# 1. verify-skill-metadata.sh
printf '[1/7] verify-skill-metadata.sh\n'
check_cmd_verbose "verify-skill-metadata" \
    bash "${REPO_ROOT}/scripts/verify-skill-metadata.sh" \
        --skills-dir "${REPO_ROOT}/skills"

# 2. verify-skill-frontmatter.sh
printf '[2/7] verify-skill-frontmatter.sh\n'
check_cmd_verbose "verify-skill-frontmatter" \
    bash "${REPO_ROOT}/scripts/verify-skill-frontmatter.sh" \
        --skills-dir "${REPO_ROOT}/skills"

# 3. shellcheck — new/changed scripts in this branch
printf '[3/7] shellcheck on stages_lib scripts and test files\n'
SHELL_TARGETS=(
    "${REPO_ROOT}/hooks/session-start.sh"
    "${REPO_ROOT}/tests/e2e/test-stages-walking-skeleton.sh"
    "${REPO_ROOT}/tests/test-phase-2-verification.sh"
)
check_cmd_verbose "shellcheck" \
    shellcheck -x "${SHELL_TARGETS[@]}"

# 4. pytest — stages_lib unit tests
printf '[4/7] pytest stages_lib unit tests\n'
# Resolve uv venv: prefer repo-local, fall back to main repo.
VENV_PYTHON=""
for candidate in \
    "${REPO_ROOT}/.board-superpowers/.venv/bin/python3" \
    "${HOME}/.board-superpowers/.venv/bin/python3"; do
    if [ -x "${candidate}" ]; then VENV_PYTHON="${candidate}"; break; fi
done
# Final fallback: use system python3 if no venv found.
VENV_PYTHON="${VENV_PYTHON:-python3}"

check_cmd_verbose "pytest-stages_lib" \
    "${VENV_PYTHON}" -m pytest "${REPO_ROOT}/scripts/stages_lib/" -q

# 5. test-common-sh-stage-helpers.sh
printf '[5/7] test-common-sh-stage-helpers.sh\n'
check_cmd_verbose "test-common-sh-stage-helpers" \
    bash "${REPO_ROOT}/tests/test-common-sh-stage-helpers.sh"

# 6. test-hook-invoke-marker.sh
printf '[6/7] test-hook-invoke-marker.sh\n'
check_cmd_verbose "test-hook-invoke-marker" \
    bash "${REPO_ROOT}/tests/test-hook-invoke-marker.sh"

# 7. test-skills-edit-gate.sh
printf '[7/7] test-skills-edit-gate.sh\n'
check_cmd_verbose "test-skills-edit-gate" \
    bash "${REPO_ROOT}/tests/test-skills-edit-gate.sh"

# Summary
printf '\n=== Phase 2 verification: %d passed, %d failed ===\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
