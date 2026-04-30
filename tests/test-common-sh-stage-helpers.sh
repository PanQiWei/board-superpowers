#!/usr/bin/env bash
# tests/test-common-sh-stage-helpers.sh — TDD for stage-aware helpers added
# to scripts/lib/common.sh in Card #67 Phase 2 Batch 3 (T2.7).
#
# Covers:
#   T2.7-01  bsp_settings_path returns correct path for all 4 localities
#   T2.7-02  bsp_repo_identity returns lowercase owner/repo slug
#   T2.7-03  bsp_stage_state_set + bsp_stage_state_get round-trips correctly
#   T2.7-04  bsp_stage_state_get returns empty when stage absent
#   T2.7-05  bsp_settings_read returns empty string when file absent
#   T2.7-06  v0.5.0+ helpers still callable (bsp_plugin_root smoke)
#   T2.7-07  bsp_settings_path rejects unknown locality
#   T2.7-08  bsp_repo_identity returns lowercase slug even with mixed-case remote
#
# Hermeticity: uses tmp dirs for HOME; never touches the real
#   ~/.board-superpowers. All git operations run in isolated tmp repos.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMMON_SH="${PLUGIN_ROOT}/scripts/lib/common.sh"

if [ ! -f "${COMMON_SH}" ]; then
    printf 'FATAL: %s not found\n' "${COMMON_SH}" >&2
    exit 99
fi

PASS=0
FAIL=0
ERRORS=0

assert_eq() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    if [ "${actual}" = "${expected}" ]; then
        printf '  PASS — %s\n' "${label}"
        PASS=$((PASS + 1))
    else
        printf '  FAIL — %s\n    expected: %q\n    actual:   %q\n' \
            "${label}" "${expected}" "${actual}" >&2
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local label="$1"
    local needle="$2"
    local haystack="$3"
    if printf '%s' "${haystack}" | grep -qF "${needle}"; then
        printf '  PASS — %s\n' "${label}"
        PASS=$((PASS + 1))
    else
        printf '  FAIL — %s\n    needle: %q\n    haystack: %q\n' \
            "${label}" "${needle}" "${haystack}" >&2
        FAIL=$((FAIL + 1))
    fi
}

assert_nonzero() {
    local label="$1"
    local exit_code="$2"
    if [ "${exit_code}" -ne 0 ]; then
        printf '  PASS — %s (exit %d)\n' "${label}" "${exit_code}"
        PASS=$((PASS + 1))
    else
        printf '  FAIL — %s (expected non-zero, got 0)\n' "${label}" >&2
        FAIL=$((FAIL + 1))
    fi
}

assert_nonempty() {
    local label="$1"
    local value="$2"
    if [ -n "${value}" ]; then
        printf '  PASS — %s\n' "${label}"
        PASS=$((PASS + 1))
    else
        printf '  FAIL — %s (expected non-empty, got empty)\n' "${label}" >&2
        FAIL=$((FAIL + 1))
    fi
}

# ---------------------------------------------------------------------------
# T2.7-01  bsp_settings_path returns correct path for all 4 localities
# ---------------------------------------------------------------------------
printf '\n=== T2.7-01: bsp_settings_path — 4 localities ===\n'
TMPHOME="$(mktemp -d)"
TMPREPO="$(mktemp -d)"
IDENTITY="PanQiWei/board-superpowers"

result="$(bash -c "
    set -euo pipefail
    HOME='${TMPHOME}'
    source '${COMMON_SH}'
    bsp_settings_path 'host-shared' '${TMPHOME}' '${TMPREPO}' '${IDENTITY}'
")"
assert_eq "host-shared path" "${TMPHOME}/.board-superpowers/settings.yml" "${result}"

result="$(bash -c "
    set -euo pipefail
    HOME='${TMPHOME}'
    source '${COMMON_SH}'
    bsp_settings_path 'repo-shared' '${TMPHOME}' '${TMPREPO}' '${IDENTITY}'
")"
assert_eq "repo-shared path (HOST side)" "${TMPHOME}/.board-superpowers/repos/${IDENTITY}/settings.yml" "${result}"

result="$(bash -c "
    set -euo pipefail
    HOME='${TMPHOME}'
    source '${COMMON_SH}'
    bsp_settings_path 'repo-git' '${TMPHOME}' '${TMPREPO}' '${IDENTITY}'
")"
assert_eq "repo-git path" "${TMPREPO}/.board-superpowers/settings.yml" "${result}"

result="$(bash -c "
    set -euo pipefail
    HOME='${TMPHOME}'
    source '${COMMON_SH}'
    bsp_settings_path 'repo-clone' '${TMPHOME}' '${TMPREPO}' '${IDENTITY}'
")"
assert_eq "repo-clone path" "${TMPREPO}/.board-superpowers/settings.local.yml" "${result}"

# repo-shared must NOT start with TMPREPO (it's host-side)
assert_nonzero "repo-shared does NOT start with TMPREPO" \
    "$(bash -c "
        set -euo pipefail
        HOME='${TMPHOME}'
        source '${COMMON_SH}'
        p=\"\$(bsp_settings_path 'repo-shared' '${TMPHOME}' '${TMPREPO}' '${IDENTITY}')\"
        case \"\${p}\" in
            ${TMPREPO}*) exit 0 ;;  # bad: starts with TMPREPO
            *)           exit 1 ;;  # good: does not start with TMPREPO
        esac
    " ; echo $?)"

rm -rf "${TMPHOME}" "${TMPREPO}"

# ---------------------------------------------------------------------------
# T2.7-07  bsp_settings_path rejects unknown locality
# ---------------------------------------------------------------------------
printf '\n=== T2.7-07: bsp_settings_path rejects unknown locality ===\n'
TMPHOME="$(mktemp -d)"
TMPREPO="$(mktemp -d)"
exit_code=0
bash -c "
    set -euo pipefail
    HOME='${TMPHOME}'
    source '${COMMON_SH}'
    bsp_settings_path 'bad-locality' '${TMPHOME}' '${TMPREPO}' 'X/Y'
" 2>/dev/null || exit_code=$?
assert_nonzero "unknown locality exits non-zero" "${exit_code}"
rm -rf "${TMPHOME}" "${TMPREPO}"

# ---------------------------------------------------------------------------
# T2.7-05  bsp_settings_read returns empty string when file absent
# ---------------------------------------------------------------------------
printf '\n=== T2.7-05: bsp_settings_read returns empty when absent ===\n'
TMPHOME="$(mktemp -d)"
TMPREPO="$(mktemp -d)"
result="$(bash -c "
    set -euo pipefail
    HOME='${TMPHOME}'
    source '${COMMON_SH}'
    bsp_settings_read 'host-shared' '${TMPHOME}' '${TMPREPO}' 'X/Y'
")"
assert_eq "read absent file → empty string" "" "${result}"
rm -rf "${TMPHOME}" "${TMPREPO}"

# ---------------------------------------------------------------------------
# T2.7-02  bsp_repo_identity returns lowercase owner/repo slug
# ---------------------------------------------------------------------------
printf '\n=== T2.7-02: bsp_repo_identity ===\n'
TMPREPO="$(mktemp -d)"
git -C "${TMPREPO}" init -q
git -C "${TMPREPO}" remote add origin "https://github.com/OwnerName/RepoName.git"
result="$(bash -c "
    set -euo pipefail
    source '${COMMON_SH}'
    bsp_repo_identity '${TMPREPO}'
")"
assert_eq "repo_identity lowercase" "ownername/reponame" "${result}"
rm -rf "${TMPREPO}"

# ---------------------------------------------------------------------------
# T2.7-08  bsp_repo_identity lowercase even with SSH remote
# ---------------------------------------------------------------------------
printf '\n=== T2.7-08: bsp_repo_identity SSH remote ===\n'
TMPREPO="$(mktemp -d)"
git -C "${TMPREPO}" init -q
git -C "${TMPREPO}" remote add origin "git@github.com:MyOrg/MyRepo.git"
result="$(bash -c "
    set -euo pipefail
    source '${COMMON_SH}'
    bsp_repo_identity '${TMPREPO}'
")"
assert_eq "repo_identity from SSH remote (lowercase)" "myorg/myrepo" "${result}"
rm -rf "${TMPREPO}"

# ---------------------------------------------------------------------------
# T2.7-03  bsp_stage_state_set + bsp_stage_state_get round-trip
# ---------------------------------------------------------------------------
printf '\n=== T2.7-03: bsp_stage_state_set + bsp_stage_state_get round-trip ===\n'
TMPHOME="$(mktemp -d)"
TMPREPO="$(mktemp -d)"
git -C "${TMPREPO}" init -q
git -C "${TMPREPO}" remote add origin "https://github.com/TestOwner/testrepo.git"
mkdir -p "${TMPHOME}/.board-superpowers/repos/testowner/testrepo"

set_output="$(bash -c "
    set -euo pipefail
    HOME='${TMPHOME}'
    source '${COMMON_SH}'
    bsp_stage_state_set 'm1.host.create-state-dir' 'applied' '1' 'abc123def456' '${TMPREPO}'
" 2>&1)" || {
    printf '  FAIL — bsp_stage_state_set returned non-zero: %s\n' "${set_output}" >&2
    FAIL=$((FAIL + 1))
}

get_output="$(bash -c "
    set -euo pipefail
    HOME='${TMPHOME}'
    source '${COMMON_SH}'
    bsp_stage_state_get 'm1.host.create-state-dir' '${TMPREPO}'
" 2>&1)"

assert_contains "round-trip: status=applied" "applied" "${get_output}"
assert_contains "round-trip: generation=1" "1" "${get_output}"
assert_contains "round-trip: hash=abc123def456" "abc123def456" "${get_output}"
rm -rf "${TMPHOME}" "${TMPREPO}"

# ---------------------------------------------------------------------------
# T2.7-04  bsp_stage_state_get returns empty when stage absent
# ---------------------------------------------------------------------------
printf '\n=== T2.7-04: bsp_stage_state_get absent stage ===\n'
TMPHOME="$(mktemp -d)"
TMPREPO="$(mktemp -d)"
git -C "${TMPREPO}" init -q
git -C "${TMPREPO}" remote add origin "https://github.com/TestOwner/testrepo.git"

result="$(bash -c "
    set -euo pipefail
    HOME='${TMPHOME}'
    source '${COMMON_SH}'
    bsp_stage_state_get 'nonexistent.stage' '${TMPREPO}' 2>/dev/null || true
")"
assert_eq "absent stage → empty output" "" "${result}"
rm -rf "${TMPHOME}" "${TMPREPO}"

# ---------------------------------------------------------------------------
# T2.7-06  v0.5.0+ helpers still callable (bsp_plugin_root smoke)
# ---------------------------------------------------------------------------
printf '\n=== T2.7-06: v0.5.0+ helpers preserved ===\n'
for fn in bsp_plugin_root bsp_resolve_active_projection bsp_resolve_audit_db_url bsp_audit_local_write; do
    present="$(bash -c "
        set -euo pipefail
        source '${COMMON_SH}'
        declare -F ${fn} >/dev/null && echo 'present' || echo 'MISSING'
    " 2>/dev/null)"
    assert_eq "${fn} still declared" "present" "${present}"
done

# bsp_plugin_root must return non-empty
plugin_root="$(bash -c "
    set -euo pipefail
    source '${COMMON_SH}'
    bsp_plugin_root
")"
assert_nonempty "bsp_plugin_root returns non-empty" "${plugin_root}"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n=== Summary ===\n'
printf 'PASS: %d  FAIL: %d\n' "${PASS}" "${FAIL}"
if [ "${FAIL}" -gt 0 ]; then
    exit 1
fi
exit 0
