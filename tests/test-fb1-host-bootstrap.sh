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
#   - Atomic write: half-written temp file never lingers; mv-failure
#     leaves no .tmp file behind.
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
# Scenario 6: atomic write — mv failure leaves no half-written file
# ---------------------------------------------------------------------------
# Simulate by pre-creating the manifest path as a directory so mv fails.
# (After --force the script tries to overwrite; mv into a directory will
# error.) We assert: no .tmp file lingers; exit non-zero.
printf 'Scenario 6: atomic write — mv failure leaves no .tmp\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
PLUGIN_ROOT="${TMP}/plugin"
mkdir -p "${HOME_DIR}/.board-superpowers"
make_stub_plugin_root "0.2.0" "${PLUGIN_ROOT}"

# Make the manifest path a DIRECTORY (not a file) so the atomic mv
# encounters a non-overwritable target.
mkdir -p "${HOME_DIR}/.board-superpowers/manifest.yml"

set +e
run_bootstrap "${HOME_DIR}" "${PLUGIN_ROOT}" --force >/dev/null 2>&1
RC=$?
set -e

assert_eq 'mv-failure exit 1' '1' "${RC}"
check_not 'no leftover manifest.yml.tmp after mv failure' \
    test -f "${HOME_DIR}/.board-superpowers/manifest.yml.tmp"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\nResults: %d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" = "0" ]
