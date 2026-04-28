#!/usr/bin/env bash
# tests/unit/test-session-start-observer.sh — AC4 SessionStart observer.
#
# Verifies hooks/session-start.sh (a) emits an audit-pending dep-alert
# when the wakeup sentinel exists, (b) finishes well under the 10s
# timeout (latency budget per 02-hook-contracts.md), and (c) does NOT
# call audit-flush-pending.sh — the hook is observer-only because
# flush latency is incompatible with the 10s hook budget.

set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT
export HOME="${TMPDIR}/fake-home"
mkdir -p "${HOME}/.board-superpowers"

# Pre-existing manifest + state.yml so the hook does not also fire an
# INVOKE: bootstrapping-repo marker (we only care about the audit
# observer block here).
cat > "${HOME}/.board-superpowers/manifest.yml" <<EOF
schema_version: 2
host_bootstrapped_at: "2026-04-01T00:00:00Z"
last_seen_version: "0.4.0"
uv_version: "0.4.0"
EOF
chmod 0644 "${HOME}/.board-superpowers/manifest.yml"

# Create sentinel + last-flush
touch "${HOME}/.board-superpowers/audit-pending.sentinel"
echo "0" > "${HOME}/.board-superpowers/audit-last-flush"

# Run hook with strict latency budget
START_NS="$(python3 -c 'import time; print(int(time.time()*1000000000))')"

# Stub stdin payload (CC SessionStart format). cwd is a non-git temp
# dir so the hook's git-aware probe degrades gracefully and the per-
# repo state.yml branch is skipped.
HOOK_OUT="$(printf '{"hook_event_name":"SessionStart","cwd":"%s"}' "${TMPDIR}" \
    | bash "${ROOT}/hooks/session-start.sh" 2>&1 || true)"

END_NS="$(python3 -c 'import time; print(int(time.time()*1000000000))')"
DELTA_MS=$(( (END_NS - START_NS) / 1000000 ))

# Assert: hook completed under 1000ms (well under 10s budget; should be ~50ms)
[ "${DELTA_MS}" -lt 1000 ] \
    || { echo "FAIL: hook latency ${DELTA_MS}ms > 1000ms"; exit 1; }

# Assert: hook output contains audit-pending dep-alert text
echo "${HOOK_OUT}" | grep -qE 'audit-pending|outbox.*unflushed|pending.*rows' \
    || { echo "FAIL: dep-alert missing in hook output"; echo "${HOOK_OUT}"; exit 1; }

# Assert: sentinel still present (hook is observer; doesn't flush)
[ -f "${HOME}/.board-superpowers/audit-pending.sentinel" ] \
    || { echo "FAIL: sentinel deleted by hook (observer should NOT flush)"; exit 1; }

echo "PASS (latency=${DELTA_MS}ms)"
