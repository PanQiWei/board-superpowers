#!/usr/bin/env bash
# tests/install-post-merge-cron-darwin.sh — dry-run verification that
# install-post-merge-cron.sh produces a syntactically valid launchd plist
# on macOS.
#
# SKIP on non-Darwin: prints a SKIP message and exits 0.
#
# Verification: uses `plutil -lint` to validate the generated plist file.
# Does NOT actually load the plist (no `launchctl load`). The fake
# launchctl shim verifies only that the script calls `launchctl load`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPT_UNDER_TEST="${PLUGIN_ROOT}/scripts/install-post-merge-cron.sh"

if [ ! -f "${SCRIPT_UNDER_TEST}" ]; then
    printf 'FATAL: %s not found\n' "${SCRIPT_UNDER_TEST}" >&2
    exit 99
fi

# --- Platform guard ---------------------------------------------------------

PLATFORM="$(uname -s)"
if [ "${PLATFORM}" != "Darwin" ]; then
    printf 'SKIP: install-post-merge-cron-darwin.sh requires Darwin (got %s)\n' "${PLATFORM}"
    exit 0
fi

TMPHOME="$(mktemp -d)"
TMPBIN="$(mktemp -d)"
TMPROOT="$(mktemp -d)"
trap 'rm -rf "${TMPHOME}" "${TMPBIN}" "${TMPROOT}"' EXIT

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

# ---------------------------------------------------------------------------
# Set up a stub plugin root with a real post-merge-cleanup.sh stub
# ---------------------------------------------------------------------------

mkdir -p "${TMPROOT}/scripts/lib"
# Create a minimal common.sh stub so install-post-merge-cron.sh can source it.
cp "${PLUGIN_ROOT}/scripts/lib/common.sh" "${TMPROOT}/scripts/lib/common.sh"
# Copy the real cleanup script (the plist path refers to it literally).
cp "${PLUGIN_ROOT}/scripts/post-merge-cleanup.sh" "${TMPROOT}/scripts/post-merge-cleanup.sh"
# The script derives PLUGIN_ROOT from BASH_SOURCE; put a minimal
# .claude-plugin/plugin.json so bsp_plugin_root works.
mkdir -p "${TMPROOT}/.claude-plugin"
printf '{"name":"board-superpowers","version":"0.2.0"}\n' > "${TMPROOT}/.claude-plugin/plugin.json"

# ---------------------------------------------------------------------------
# Fake launchctl: capture calls without actually loading anything
# ---------------------------------------------------------------------------

LAUNCHCTL_CALLS_FILE="${TMPHOME}/launchctl-calls"
cat > "${TMPBIN}/launchctl" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${LAUNCHCTL_CALLS_FILE}"
# Pretend success for both unload (may 'fail') and load.
exit 0
STUB
chmod +x "${TMPBIN}/launchctl"

# ---------------------------------------------------------------------------
# Run install-post-merge-cron.sh (Darwin path)
# ---------------------------------------------------------------------------

printf '\nRunning install-post-merge-cron.sh --card 7 --owner acme ...\n'

PLIST_DIR="${TMPHOME}/Library/LaunchAgents"
PLIST_PATH="${PLIST_DIR}/com.board-superpowers.post-merge-acme-7.plist"

set +e
HOME="${TMPHOME}" \
    PATH="${TMPBIN}:/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin" \
    CLAUDE_PLUGIN_ROOT="${TMPROOT}" \
    bash "${SCRIPT_UNDER_TEST}" \
        --card 7 \
        --owner acme \
        --poll-interval-minutes 5 \
        --timeout-hours 12 \
    2>/dev/null
RC=$?
set -e

check "exit code 0" test "${RC}" -eq 0

check "plist file was created" test -f "${PLIST_PATH}"

# ---------------------------------------------------------------------------
# Validate plist syntax with plutil
# ---------------------------------------------------------------------------

if [ -f "${PLIST_PATH}" ]; then
    check "plist passes plutil -lint" plutil -lint "${PLIST_PATH}"

    # Check that key elements are present in the plist.
    check "plist contains StartInterval" \
        grep -q "StartInterval" "${PLIST_PATH}"

    check "plist contains the label" \
        grep -q "com.board-superpowers.post-merge-acme-7" "${PLIST_PATH}"

    check "plist references post-merge-cleanup.sh" \
        grep -q "post-merge-cleanup.sh" "${PLIST_PATH}"
fi

# ---------------------------------------------------------------------------
# Verify launchctl load was called
# ---------------------------------------------------------------------------

if [ -f "${LAUNCHCTL_CALLS_FILE}" ]; then
    check "launchctl load was called" \
        grep -q "load" "${LAUNCHCTL_CALLS_FILE}"
fi

# ---------------------------------------------------------------------------
# Idempotency: run again; plist should be replaced without error
# ---------------------------------------------------------------------------

set +e
HOME="${TMPHOME}" \
    PATH="${TMPBIN}:/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin" \
    CLAUDE_PLUGIN_ROOT="${TMPROOT}" \
    bash "${SCRIPT_UNDER_TEST}" \
        --card 7 \
        --owner acme \
        --poll-interval-minutes 5 \
        --timeout-hours 12 \
    2>/dev/null
RC2=$?
set -e

check "idempotent re-run exit code 0" test "${RC2}" -eq 0
check "plist still present after re-run" test -f "${PLIST_PATH}"

if [ -f "${PLIST_PATH}" ]; then
    check "re-run plist still passes plutil -lint" plutil -lint "${PLIST_PATH}"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\nResults: %d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
