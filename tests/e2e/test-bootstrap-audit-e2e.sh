#!/usr/bin/env bash
# tests/e2e/test-bootstrap-audit-e2e.sh
#
# End-to-end: fresh-repo bootstrap audit pipeline.
# Simulates the SKILL emitting 9 bootstrap audit rows via audit-log-write.sh
# --mode bootstrap-pending → jsonl outbox → fast-path flush → DB.
#
# Asserts (per design.md §3.6):
#   1. audit_log table contains exactly 9 rows after end-of-bootstrap flush
#   2. jsonl has 0 rows with forbidden modes (contract-violation /
#      degraded-db-unavailable / audit-dead-letter)
#   3. all 9 DB rows have non-NULL event_uuid
#   4. all 9 jsonl rows transitioned to status=processed (preserved, not deleted)
#   5. audit-health summary line emitted with "9 of 9 ... 0 remain in jsonl"
#   6. sentinel deleted after flush (no pending rows remain)
#
# Runs against tmp SQLite DB; HOME isolated to tmp dir; PG/MySQL containers
# deferred (this test covers SQLite only).

set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT

# Isolate host state
export HOME="${TMPDIR}/fake-home"
mkdir -p "${HOME}/.board-superpowers"

# Configure SQLite DB via env (no credentials.yml needed)
DB="${TMPDIR}/audit.db"
export BOARD_SP_AUDIT_DB_URL="sqlite:////${DB}"

# Apply v2 schema (simulates what audit-init.sh would do at bootstrap step 2g)
sqlite3 "${DB}" < "${ROOT}/scripts/lib/audit-schema.sqlite.sql"

# Record bootstrap session start (mirrors what bootstrap-project.sh does at start)
BOOTSTRAP_SESSION_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
sleep 1

# Simulate 9 SKILL emits during bootstrap (action_ids 200..208 in execution order).
#
# Set BSP_SKIP_GUARD=1 during the emit loop to suppress the opportunistic
# flush guard in audit-log-write.sh (lines 103-124). In a real bootstrap
# the guard CAN fire mid-emit (background-forks audit-flush-pending.sh
# when LAST_FLUSH_FILE is stale by >60s), which transitions some
# already-emitted rows to status=processed before all 9 emits complete.
# That's design-correct runtime behavior; we suppress it here ONLY so
# the "9 pending before flush" precondition is deterministic. The
# end-of-bootstrap explicit flush (audit-flush-pending.sh below) runs
# WITHOUT BSP_SKIP_GUARD and exercises the same code path.
for action_id in 200 201 202 203 204 205 206 207 208; do
    BSP_SKIP_GUARD=1 bash "${ROOT}/scripts/audit-log-write.sh" \
        --action-id "${action_id}" \
        --decision A \
        --skill bootstrapping-repo \
        --approval-stage auto \
        --outcome success \
        --payload "{\"step\":${action_id}}" \
        --mode bootstrap-pending
done

# At this point all 9 rows are in jsonl with status=pending; sentinel exists
SENTINEL="${HOME}/.board-superpowers/audit-pending.sentinel"
[ -f "${SENTINEL}" ] || { echo "FAIL: sentinel not created during emit phase"; exit 1; }

JSONL=$(find "${HOME}/.board-superpowers/repos/" -name 'audit-local.jsonl' 2>/dev/null | head -1)
[ -f "${JSONL}" ] || { echo "FAIL: jsonl not created"; exit 1; }

PENDING_BEFORE=$(grep -c '"status": "pending"' "${JSONL}" || true)
[ "${PENDING_BEFORE}" = 9 ] || { echo "FAIL: expected 9 pending before flush, got ${PENDING_BEFORE}"; exit 1; }

# Fast-path flush (mirrors bootstrap-project.sh Step 3.5).
# Run WITHOUT BSP_SKIP_GUARD to exercise the real explicit-flush path.
bash "${ROOT}/scripts/audit-flush-pending.sh"

# Health summary (mirrors bootstrap-project.sh Step 3.6)
# shellcheck source=/dev/null
. "${ROOT}/scripts/lib/common.sh"
HEALTH_OUT=$(bsp_audit_health_summary "${BOOTSTRAP_SESSION_TS}" 2>&1)

# ──── Assertions ────────────────────────────────────────────────────────

# Assert 1: 9 rows in DB
DB_COUNT=$(sqlite3 "${DB}" 'SELECT COUNT(*) FROM audit_log')
[ "${DB_COUNT}" = 9 ] || { echo "FAIL [Assert 1]: DB count = ${DB_COUNT}, expected 9"; exit 1; }

# Assert 2: zero forbidden modes in jsonl
FORBIDDEN=$(grep -cE '"mode":[[:space:]]*"(contract-violation|degraded-db-unavailable|audit-dead-letter)"' "${JSONL}" 2>/dev/null || true)
[ "${FORBIDDEN:-0}" = 0 ] || { echo "FAIL [Assert 2]: ${FORBIDDEN} forbidden-mode rows in jsonl"; exit 1; }

# Assert 3: all 9 DB rows have non-NULL event_uuid
UUID_COUNT=$(sqlite3 "${DB}" 'SELECT COUNT(*) FROM audit_log WHERE event_uuid IS NOT NULL')
[ "${UUID_COUNT}" = 9 ] || { echo "FAIL [Assert 3]: ${UUID_COUNT}/9 rows have event_uuid"; exit 1; }

# Assert 4: all 9 jsonl rows transitioned to status=processed
PROCESSED=$(grep -c '"status": "processed"' "${JSONL}" || true)
[ "${PROCESSED}" = 9 ] || { echo "FAIL [Assert 4]: ${PROCESSED}/9 rows processed"; exit 1; }

PENDING_AFTER=$(grep -c '"status": "pending"' "${JSONL}" 2>/dev/null || true)
[ "${PENDING_AFTER:-0}" = 0 ] || { echo "FAIL [Assert 4b]: ${PENDING_AFTER} pending rows remain after flush"; exit 1; }

# Assert 5: health summary "9 of 9 ... 0 remain in jsonl"
echo "${HEALTH_OUT}" | grep -qE '9 of 9' || { echo "FAIL [Assert 5a]: health output missing '9 of 9'; got: ${HEALTH_OUT}"; exit 1; }
echo "${HEALTH_OUT}" | grep -qE '0 remain' || { echo "FAIL [Assert 5b]: health output missing '0 remain'; got: ${HEALTH_OUT}"; exit 1; }

# Assert 6: sentinel deleted after flush (no pending rows remain)
[ ! -f "${SENTINEL}" ] || { echo "FAIL [Assert 6]: sentinel not deleted post-flush"; exit 1; }

echo "PASS: 9/9 bootstrap audit rows landed in DB; jsonl status=processed; sentinel cleaned"
