#!/usr/bin/env bash
# tests/test-fb1-host-bootstrap.sh — assert scripts/bootstrap-host.sh
# satisfies the F-B1 host bootstrap contract per
# docs/architecture/0002-product-features-and-flows/05-bootstrap-surface.md
# § 1.5.1 and 07-path-conventions.md "Per-host layout".
#
# Contracts under test:
#   - Cold start: writes ~/.board-superpowers/manifest.yml with
#     schema_version: 1 + ISO-8601 host_bootstrapped_at + plugin version
#     last_seen_version. Directory mode 0700; file mode 0644.
#   - Idempotent re-run: same version, manifest already valid → no
#     overwrite (mtime preserved), exit 0.
#   - Version refresh: manifest exists with older last_seen_version →
#     last_seen_version updated; host_bootstrapped_at preserved.
#   - --force flag: overwrite even when manifest is already correct.
#   - Bad --plugin-root: exit 1, helpful error.
#   - Defensive guard: target manifest path is unexpectedly a
#     directory → exit 1, no .tmp file lingers.
#   - Concurrent runs: two parallel invocations both succeed, exactly
#     one manifest.yml exists, no .tmp leaks (proves per-process
#     mktemp scratch files plus rename(2) atomicity).
#   - YAML whitespace tolerance: `key : "value"` (extra space before
#     colon) parses correctly during version-refresh detection.
#
# Hermeticity: every scenario uses a fresh tmp HOME plus a fresh tmp
# plugin-root containing a stub .claude-plugin/plugin.json. Nothing
# touches the real ~/.board-superpowers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT_REAL="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPT_UNDER_TEST="${PLUGIN_ROOT_REAL}/scripts/bootstrap-host.sh"

if [ ! -f "${SCRIPT_UNDER_TEST}" ]; then
    printf 'FATAL: %s not found\n' "${SCRIPT_UNDER_TEST}" >&2
    exit 99
fi

PASS=0
FAIL=0

check() {
    local label="$1"
    shift
    if "$@"; then
        printf '  PASS — %s\n' "${label}"
        PASS=$((PASS + 1))
    else
        printf '  FAIL — %s\n' "${label}" >&2
        FAIL=$((FAIL + 1))
    fi
}

check_not() {
    local label="$1"
    shift
    if "$@"; then
        printf '  FAIL — %s\n' "${label}" >&2
        FAIL=$((FAIL + 1))
    else
        printf '  PASS — %s\n' "${label}"
        PASS=$((PASS + 1))
    fi
}

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

# Make a stub plugin root containing only .claude-plugin/plugin.json
# with the requested version. Returns the path on stdout.
make_stub_plugin_root() {
    local version="$1"
    local target_dir="$2"
    mkdir -p "${target_dir}/.claude-plugin"
    cat > "${target_dir}/.claude-plugin/plugin.json" <<EOF
{
  "name": "board-superpowers",
  "version": "${version}",
  "description": "stub for tests",
  "license": "MIT"
}
EOF
}

# Cross-platform "stat -c %a path" — macOS uses -f %A, GNU uses -c %a.
file_mode() {
    local path="$1"
    if stat -f '%A' "${path}" >/dev/null 2>&1; then
        stat -f '%A' "${path}"
    else
        stat -c '%a' "${path}"
    fi
}

run_bootstrap() {
    local home_dir="$1"; shift
    local plugin_root="$1"; shift
    HOME="${home_dir}" bash "${SCRIPT_UNDER_TEST}" --plugin-root "${plugin_root}" "$@"
}

# ---------------------------------------------------------------------------
# Scenario 1: cold start writes manifest with correct schema + perms
# ---------------------------------------------------------------------------
printf 'Scenario 1: cold start (manifest absent)\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
PLUGIN_ROOT="${TMP}/plugin"
mkdir -p "${HOME_DIR}"
make_stub_plugin_root "0.2.0" "${PLUGIN_ROOT}"

MANIFEST="${HOME_DIR}/.board-superpowers/manifest.yml"
STATE_DIR="${HOME_DIR}/.board-superpowers"

# Capture stdout — should print the manifest path on success.
STDOUT="$(run_bootstrap "${HOME_DIR}" "${PLUGIN_ROOT}" 2>/dev/null)"
RC=$?

assert_eq 'cold start exit 0' '0' "$(printf '%d' "${RC}")"
check 'manifest file created' test -f "${MANIFEST}"
assert_eq 'stdout is the manifest path' "${MANIFEST}" "${STDOUT}"

# Permissions
assert_eq 'state dir mode 0700' '700' "$(file_mode "${STATE_DIR}")"
assert_eq 'manifest file mode 0644' '644' "$(file_mode "${MANIFEST}")"

# Content shape
check 'schema_version: 1 present' \
    grep -Fxq 'schema_version: 1' "${MANIFEST}"
check 'last_seen_version: "0.2.0" present' \
    grep -Fxq 'last_seen_version: "0.2.0"' "${MANIFEST}"
check 'host_bootstrapped_at present + ISO-8601 shape' \
    grep -Eq '^host_bootstrapped_at: "[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"$' "${MANIFEST}"

# Atomic write: no leftover .tmp file
check_not 'no leftover manifest.yml.tmp' test -f "${MANIFEST}.tmp"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 2: idempotent re-run (same version) — no overwrite
# ---------------------------------------------------------------------------
printf 'Scenario 2: idempotent re-run (same version)\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
PLUGIN_ROOT="${TMP}/plugin"
mkdir -p "${HOME_DIR}"
make_stub_plugin_root "0.2.0" "${PLUGIN_ROOT}"

# First write
run_bootstrap "${HOME_DIR}" "${PLUGIN_ROOT}" >/dev/null 2>&1

MANIFEST="${HOME_DIR}/.board-superpowers/manifest.yml"

# Capture mtime before re-run (use stat — portable form covered above).
mtime_before() {
    if stat -f '%m' "${MANIFEST}" >/dev/null 2>&1; then
        stat -f '%m' "${MANIFEST}"
    else
        stat -c '%Y' "${MANIFEST}"
    fi
}
BEFORE="$(mtime_before)"

# Sleep 1.1s so any rewrite would change mtime (mtime resolution = 1s on
# many filesystems). Necessary because Scenario 2 must DETECT a no-op.
sleep 1.1

# Re-run with same version
set +e
run_bootstrap "${HOME_DIR}" "${PLUGIN_ROOT}" >/dev/null 2>&1
RC=$?
set -e
AFTER="$(mtime_before)"

assert_eq 'idempotent re-run exit 0' '0' "${RC}"
assert_eq 'manifest mtime unchanged (no overwrite)' "${BEFORE}" "${AFTER}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 3: version refresh — older last_seen_version, bump to current
# ---------------------------------------------------------------------------
printf 'Scenario 3: version refresh (older last_seen_version)\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
PLUGIN_ROOT="${TMP}/plugin"
mkdir -p "${HOME_DIR}/.board-superpowers"
make_stub_plugin_root "0.2.0" "${PLUGIN_ROOT}"

MANIFEST="${HOME_DIR}/.board-superpowers/manifest.yml"
ORIGINAL_TS='2026-01-15T08:00:00Z'
cat > "${MANIFEST}" <<EOF
schema_version: 1
host_bootstrapped_at: "${ORIGINAL_TS}"
last_seen_version: "0.1.0"
EOF
chmod 0644 "${MANIFEST}"
chmod 0700 "${HOME_DIR}/.board-superpowers"

set +e
run_bootstrap "${HOME_DIR}" "${PLUGIN_ROOT}" >/dev/null 2>&1
RC=$?
set -e

assert_eq 'version refresh exit 0' '0' "${RC}"
check 'last_seen_version updated to "0.2.0"' \
    grep -Fxq 'last_seen_version: "0.2.0"' "${MANIFEST}"
check_not 'old last_seen_version: "0.1.0" gone' \
    grep -Fxq 'last_seen_version: "0.1.0"' "${MANIFEST}"
check 'host_bootstrapped_at preserved (NOT overwritten)' \
    grep -Fxq "host_bootstrapped_at: \"${ORIGINAL_TS}\"" "${MANIFEST}"

# Atomic write: no leftover .tmp file after refresh
check_not 'no leftover manifest.yml.tmp after refresh' test -f "${MANIFEST}.tmp"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 4: --force overwrites even when manifest is already correct
# ---------------------------------------------------------------------------
printf 'Scenario 4: --force flag overwrites manifest\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
PLUGIN_ROOT="${TMP}/plugin"
mkdir -p "${HOME_DIR}/.board-superpowers"
make_stub_plugin_root "0.2.0" "${PLUGIN_ROOT}"

MANIFEST="${HOME_DIR}/.board-superpowers/manifest.yml"
ORIGINAL_TS='2026-01-15T08:00:00Z'
cat > "${MANIFEST}" <<EOF
schema_version: 1
host_bootstrapped_at: "${ORIGINAL_TS}"
last_seen_version: "0.2.0"
EOF
chmod 0644 "${MANIFEST}"
chmod 0700 "${HOME_DIR}/.board-superpowers"

# Sleep so timestamps differ if --force regenerates
sleep 1.1

set +e
run_bootstrap "${HOME_DIR}" "${PLUGIN_ROOT}" --force >/dev/null 2>&1
RC=$?
set -e

assert_eq '--force exit 0' '0' "${RC}"
check 'last_seen_version remains "0.2.0"' \
    grep -Fxq 'last_seen_version: "0.2.0"' "${MANIFEST}"
check_not 'host_bootstrapped_at was overwritten by --force' \
    grep -Fxq "host_bootstrapped_at: \"${ORIGINAL_TS}\"" "${MANIFEST}"
check 'host_bootstrapped_at retains ISO-8601 shape after --force' \
    grep -Eq '^host_bootstrapped_at: "[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"$' "${MANIFEST}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 5: bad --plugin-root → exit 1 with helpful error
# ---------------------------------------------------------------------------
printf 'Scenario 5: bad --plugin-root path\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
mkdir -p "${HOME_DIR}"
NONEXISTENT="${TMP}/no-such-plugin-root"

set +e
ERR_OUT="$(HOME="${HOME_DIR}" bash "${SCRIPT_UNDER_TEST}" --plugin-root "${NONEXISTENT}" 2>&1 1>/dev/null)"
RC=$?
set -e

assert_eq 'bad --plugin-root exit 1' '1' "${RC}"
check 'stderr mentions plugin root or plugin.json problem' \
    bash -c "printf '%s' \"\${1}\" | grep -Eqi 'plugin.?root|plugin\\.json'" _ "${ERR_OUT}"
check_not 'no manifest written under bad plugin root' \
    test -f "${HOME_DIR}/.board-superpowers/manifest.yml"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 6: manifest path is unexpectedly a directory
# ---------------------------------------------------------------------------
# A bare `mv source dir/` succeeds on POSIX (moves source INTO dir),
# which would silently land manifest.yml.tmp inside a directory named
# manifest.yml and corrupt the layout. The script's defensive guard
# (refuse-if-target-is-a-directory) must short-circuit before the mv
# is attempted. We assert: exit 1, no scratch .tmp file leaks behind.
#
# (Honest naming: this scenario is NOT a generic mv-failure simulation
# — true mv failures, e.g. read-only filesystem, are hard to fake
# hermetically. This scenario locks in the dir-target gotcha guard,
# which is the realistic failure mode.)
printf 'Scenario 6: manifest path is unexpectedly a directory\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
PLUGIN_ROOT="${TMP}/plugin"
mkdir -p "${HOME_DIR}/.board-superpowers"
make_stub_plugin_root "0.2.0" "${PLUGIN_ROOT}"

# Make the manifest path a DIRECTORY (not a file) so the atomic mv
# would corrupt the layout if not guarded.
mkdir -p "${HOME_DIR}/.board-superpowers/manifest.yml"

set +e
run_bootstrap "${HOME_DIR}" "${PLUGIN_ROOT}" --force >/dev/null 2>&1
RC=$?
set -e

assert_eq 'dir-target exit 1' '1' "${RC}"
# Per-process mktemp scratch files use the pattern manifest.yml.tmp.<6>
# (trailing-Xs constraint of BSD mktemp). Assert NONE exist, and ALSO
# assert the legacy fixed-path manifest.yml.tmp does not leak.
LEFTOVER_COUNT="$(find "${HOME_DIR}/.board-superpowers" \
    -maxdepth 1 -name 'manifest.yml.tmp.*' 2>/dev/null | wc -l | tr -d ' ')"
assert_eq 'no leftover .tmp.* scratch files after dir-target guard' \
    '0' "${LEFTOVER_COUNT}"
check_not 'no legacy fixed-path manifest.yml.tmp leak' \
    test -f "${HOME_DIR}/.board-superpowers/manifest.yml.tmp"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 7: concurrent F-B1 invocations — both succeed, no .tmp leak
# ---------------------------------------------------------------------------
# Two CC sessions can hit first-run F-B1 on the same host at the same
# time. Per-process mktemp scratch files mean neither writer races on
# a shared scratch path; the final mv is rename(2)-atomic; both end up
# with a valid manifest.yml (one overwrites the other; payload is
# semantically equivalent). We assert: both exit 0, exactly one
# manifest.yml exists at the end, no .tmp scratch files leak.
printf 'Scenario 7: concurrent invocations (race-loser still clean)\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
PLUGIN_ROOT="${TMP}/plugin"
mkdir -p "${HOME_DIR}"
make_stub_plugin_root "0.2.0" "${PLUGIN_ROOT}"

MANIFEST="${HOME_DIR}/.board-superpowers/manifest.yml"

# Spawn two parallel invocations and wait. Each writes its own .tmp
# via mktemp, then races on the rename(2). POSIX guarantees the
# rename is atomic on a same-filesystem move, so one wins and the
# other harmlessly overwrites with the same payload.
set +e
HOME="${HOME_DIR}" bash "${SCRIPT_UNDER_TEST}" \
    --plugin-root "${PLUGIN_ROOT}" >/dev/null 2>&1 &
PID_A=$!
HOME="${HOME_DIR}" bash "${SCRIPT_UNDER_TEST}" \
    --plugin-root "${PLUGIN_ROOT}" >/dev/null 2>&1 &
PID_B=$!
wait "${PID_A}"; RC_A=$?
wait "${PID_B}"; RC_B=$?
set -e

assert_eq 'concurrent invocation A exit 0' '0' "${RC_A}"
assert_eq 'concurrent invocation B exit 0' '0' "${RC_B}"

MANIFEST_COUNT="$(find "${HOME_DIR}/.board-superpowers" \
    -maxdepth 1 -name 'manifest.yml' -type f 2>/dev/null | wc -l | tr -d ' ')"
assert_eq 'exactly one manifest.yml after concurrent runs' \
    '1' "${MANIFEST_COUNT}"

TMP_LEAK_COUNT="$(find "${HOME_DIR}/.board-superpowers" \
    -maxdepth 1 -name 'manifest.yml.tmp.*' 2>/dev/null | wc -l | tr -d ' ')"
assert_eq 'no .tmp scratch leaks after concurrent runs' \
    '0' "${TMP_LEAK_COUNT}"

# Sanity: the surviving manifest is well-formed.
check 'concurrent-survivor manifest has correct version' \
    grep -Fxq 'last_seen_version: "0.2.0"' "${MANIFEST}"
check 'concurrent-survivor manifest has ISO-8601 host_bootstrapped_at' \
    grep -Eq '^host_bootstrapped_at: "[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"$' "${MANIFEST}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 8: YAML whitespace tolerance — `key : "value"` parses
# ---------------------------------------------------------------------------
# A user hand-edits manifest.yml and adds an extra space before the
# colon (`last_seen_version : "0.1.0"`). YAML allows this (whitespace
# around the colon is non-significant for top-level scalars). The
# version-refresh path must still detect the older version and bump
# to the plugin's current version.
printf 'Scenario 8: YAML whitespace tolerance (key<ws>:<ws>value)\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
PLUGIN_ROOT="${TMP}/plugin"
mkdir -p "${HOME_DIR}/.board-superpowers"
make_stub_plugin_root "0.2.0" "${PLUGIN_ROOT}"

MANIFEST="${HOME_DIR}/.board-superpowers/manifest.yml"
ORIGINAL_TS='2026-02-01T08:00:00Z'
# Note the EXTRA SPACES around colons — both before and after.
cat > "${MANIFEST}" <<EOF
schema_version : 1
host_bootstrapped_at  :  "${ORIGINAL_TS}"
last_seen_version : "0.1.0"
EOF
chmod 0644 "${MANIFEST}"
chmod 0700 "${HOME_DIR}/.board-superpowers"

set +e
run_bootstrap "${HOME_DIR}" "${PLUGIN_ROOT}" >/dev/null 2>&1
RC=$?
set -e

assert_eq 'whitespace-tolerant refresh exit 0' '0' "${RC}"
check 'last_seen_version bumped to "0.2.0" despite spaced colons' \
    grep -Fxq 'last_seen_version: "0.2.0"' "${MANIFEST}"
check_not 'old last_seen_version: "0.1.0" gone after whitespace-tolerant refresh' \
    grep -Eq '^last_seen_version[[:space:]]*:[[:space:]]*"0\.1\.0"$' "${MANIFEST}"
check 'host_bootstrapped_at preserved across whitespace-tolerant refresh' \
    grep -Fxq "host_bootstrapped_at: \"${ORIGINAL_TS}\"" "${MANIFEST}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\nResults: %d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" = "0" ]
