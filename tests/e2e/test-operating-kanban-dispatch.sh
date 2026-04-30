#!/usr/bin/env bash
# tests/e2e/test-operating-kanban-dispatch.sh
#
# Integration test for #68 AC4 — bsp_resolve_active_projection helper.
# Exercises both the real path (settings.yml § modules.m10_kanban) and
# the legacy fallback (config.yml § project) per the resolution
# algorithm in skills/operating-kanban/references/backend-selection.md.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/common.sh"

PASS=0
FAIL=0
TMPDIR="$(mktemp -d -t bsp-ac4-XXXXXX)"
trap 'rm -rf "${TMPDIR}"' EXIT

assert_eq() {
    local actual="$1"
    local expected="$2"
    local label="$3"
    if [ "${actual}" = "${expected}" ]; then
        printf '[PASS] %s\n' "${label}"
        PASS=$((PASS + 1))
    else
        printf '[FAIL] %s\n  expected: %q\n  actual:   %q\n' \
            "${label}" "${expected}" "${actual}"
        FAIL=$((FAIL + 1))
    fi
}

# --- Test 1: real path with kanbans list length=1 -----------------------
test1_dir="${TMPDIR}/test1"
mkdir -p "${test1_dir}/.board-superpowers"
cat > "${test1_dir}/.board-superpowers/settings.yml" <<'EOF'
modules:
  m10_kanban:
    schema_version: 1
    projection: github-project-v2
    project_ref: PanQiWei/4
    kanbans:
      - id: primary
        state: active
        projection: github-project-v2
        project_ref: PanQiWei/4
        role: primary
EOF
result1="$(bsp_resolve_active_projection "${test1_dir}" 2>/dev/null)"
assert_eq "${result1}" "github-project-v2 PanQiWei/4" \
    "real path: kanbans len=1 returns projection + project_ref"

# --- Test 2: real path with shorthand-only (no kanbans list) ------------
test2_dir="${TMPDIR}/test2"
mkdir -p "${test2_dir}/.board-superpowers"
cat > "${test2_dir}/.board-superpowers/settings.yml" <<'EOF'
modules:
  m10_kanban:
    schema_version: 1
    projection: github-project-v2
    project_ref: PanQiWei/4
EOF
result2="$(bsp_resolve_active_projection "${test2_dir}" 2>/dev/null)"
assert_eq "${result2}" "github-project-v2 PanQiWei/4" \
    "real path: shorthand fields return projection + project_ref"

# --- Test 3: multi-kanban length>1 hard-fails ---------------------------
test3_dir="${TMPDIR}/test3"
mkdir -p "${test3_dir}/.board-superpowers"
cat > "${test3_dir}/.board-superpowers/settings.yml" <<'EOF'
modules:
  m10_kanban:
    kanbans:
      - id: primary
        projection: github-project-v2
        project_ref: PanQiWei/4
      - id: legal
        projection: jira
        project_ref: legal-team/COMPLIANCE
EOF
err3="$(bsp_resolve_active_projection "${test3_dir}" 2>&1 >/dev/null || true)"
case "${err3}" in
    *multi-kanban*v1.0*)
        printf '[PASS] multi-kanban len>1 surfaces capability error\n'
        PASS=$((PASS + 1))
        ;;
    *)
        printf '[FAIL] multi-kanban len>1: expected capability error, got: %s\n' \
            "${err3}"
        FAIL=$((FAIL + 1))
        ;;
esac

# --- Test 4: fallback path with config.yml § project --------------------
test4_dir="${TMPDIR}/test4"
mkdir -p "${test4_dir}/.board-superpowers"
cat > "${test4_dir}/.board-superpowers/config.yml" <<'EOF'
# legacy v0.4.x form
project: PanQiWei/3
EOF
result4="$(bsp_resolve_active_projection "${test4_dir}" 2>/dev/null)"
assert_eq "${result4}" "github-project-v2 PanQiWei/3" \
    "fallback path: config.yml § project resolves"

# --- Test 5: fallback path emits deprecation notice on stderr -----------
err5="$(bsp_resolve_active_projection "${test4_dir}" 2>&1 >/dev/null)"
case "${err5}" in
    *DEPRECATION*config.yml*legacy*)
        printf '[PASS] fallback path emits deprecation notice on stderr\n'
        PASS=$((PASS + 1))
        ;;
    *)
        printf '[FAIL] fallback deprecation: expected DEPRECATION message, got: %s\n' \
            "${err5}"
        FAIL=$((FAIL + 1))
        ;;
esac

# --- Test 6: no config returns non-zero ---------------------------------
test6_dir="${TMPDIR}/test6"
mkdir -p "${test6_dir}/.board-superpowers"
if bsp_resolve_active_projection "${test6_dir}" 2>/dev/null; then
    printf '[FAIL] empty config: expected non-zero exit\n'
    FAIL=$((FAIL + 1))
else
    printf '[PASS] empty config returns non-zero\n'
    PASS=$((PASS + 1))
fi

# --- Summary ------------------------------------------------------------
printf '\n=== Summary ===\nPASS: %d\nFAIL: %d\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ] || exit 1
