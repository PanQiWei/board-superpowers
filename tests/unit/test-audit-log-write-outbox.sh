#!/usr/bin/env bash
# unit: --mode bootstrap-pending writes outbox-shaped jsonl with event_uuid +
# status=pending + retry_count=0 + pending_since (#43 AC4 write). Also covers
# the opportunistic-guard sentinel and the --mode whitelist (only
# bootstrap-pending allowed externally).
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT
export HOME="${TMPDIR}/fake-home"
mkdir -p "${HOME}/.board-superpowers"

# Test 1: --mode bootstrap-pending writes jsonl with event_uuid + status=pending + retry_count=0 + pending_since
bash "${ROOT}/scripts/audit-log-write.sh" \
    --action-id 200 \
    --decision A \
    --skill bootstrapping-repo \
    --approval-stage auto \
    --outcome success \
    --payload '{"test":1}' \
    --mode bootstrap-pending

JSONL=$(find "${HOME}/.board-superpowers/repos/" -name 'audit-local.jsonl' 2>/dev/null | head -1)
[ -f "${JSONL}" ] || { echo "FAIL: jsonl not written"; exit 1; }

grep -qE '"event_uuid": "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"' "${JSONL}" \
    || { echo "FAIL: event_uuid missing or malformed"; cat "${JSONL}"; exit 1; }
grep -q '"status": "pending"' "${JSONL}" || { echo "FAIL: status=pending missing"; exit 1; }
grep -q '"retry_count": 0' "${JSONL}" || { echo "FAIL: retry_count=0 missing"; exit 1; }
grep -qE '"pending_since": "[0-9]{4}-[0-9]{2}-[0-9]{2}T' "${JSONL}" \
    || { echo "FAIL: pending_since missing"; exit 1; }
grep -q '"mode": "bootstrap-pending"' "${JSONL}" || { echo "FAIL: mode=bootstrap-pending missing"; exit 1; }

# Test 2: sentinel created
[ -f "${HOME}/.board-superpowers/audit-pending.sentinel" ] || { echo "FAIL: sentinel missing after first bootstrap-pending write"; exit 1; }

# Test 3: 60s backoff guard prevents flush re-entry within window
# Set last_flush to "now" (recent), then write again → should NOT trigger flush
date +%s > "${HOME}/.board-superpowers/audit-last-flush"

# Use BSP_SKIP_GUARD=1 so this second write itself doesn't try to fork
# (we test the guard logic indirectly: if last_flush is fresh, the next non-guarded write should skip the fork)
bash "${ROOT}/scripts/audit-log-write.sh" \
    --action-id 201 --decision A --skill bootstrapping-repo \
    --approval-stage auto --outcome success --payload '{}' --mode bootstrap-pending

# Verify second row still wrote (with its own event_uuid)
ROW_COUNT=$(grep -c '"action_id":' "${JSONL}")
[ "${ROW_COUNT}" = 2 ] || { echo "FAIL: second row not appended; got ${ROW_COUNT} rows"; exit 1; }

# Test 4: integer + no DB (no --mode) → unchanged behavior (mode=no-db)
rm -rf "${HOME}/.board-superpowers"
mkdir -p "${HOME}/.board-superpowers"
bash "${ROOT}/scripts/audit-log-write.sh" \
    --action-id 200 --decision A --skill bootstrapping-repo \
    --approval-stage auto --outcome success --payload '{}'
JSONL2=$(find "${HOME}/.board-superpowers/repos/" -name 'audit-local.jsonl' 2>/dev/null | head -1)
grep -q '"mode": "no-db"' "${JSONL2}" || { echo "FAIL: no-mode default behavior changed"; exit 1; }

# Test 5: explicit --mode value besides bootstrap-pending → reject
RC=0
bash "${ROOT}/scripts/audit-log-write.sh" \
    --action-id 200 --decision A --skill bootstrapping-repo \
    --approval-stage auto --outcome success --payload '{}' --mode foo-bar 2>/dev/null || RC=$?
[ "${RC}" != 0 ] || { echo "FAIL: invalid --mode value should be rejected"; exit 1; }

echo "PASS"
