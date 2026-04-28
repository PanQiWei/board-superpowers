#!/usr/bin/env bash
# tests/unit/test-flush-concurrent.sh — race regression for AC4 flush.
#
# Three concurrent invocations of audit-flush-pending.sh against the
# same audit-local.jsonl. Without the per-jsonl flock mutex (Task 6b),
# the atomic-rewrite step races: each worker reads the original file
# and rewrites it, and the last rename wins — earlier workers' status
# transitions are silently overwritten, dropping rows from the jsonl
# even though UNIQUE event_uuid in DB prevents duplicate INSERTs.
#
# With flock, the three workers serialize on ${jsonl}.lock; all 100
# rows transition to status=processed and DB has 100 rows.
#
# Reproduces reliably on macOS/Linux with 100 rows × 3 procs.

set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT
export HOME="${TMPDIR}/fake-home"

DB="${TMPDIR}/audit.db"
sqlite3 "${DB}" < "${ROOT}/scripts/lib/audit-schema.sqlite.sql"
export BOARD_SP_AUDIT_DB_URL="sqlite:////${DB}"

NORMALIZED="$(echo "/test/repo" | sed 's|^/||; s|/|-|g')"
JSONL_DIR="${HOME}/.board-superpowers/repos/${NORMALIZED}"
mkdir -p "${JSONL_DIR}"
JSONL="${JSONL_DIR}/audit-local.jsonl"

# Seed 100 pending rows (large enough to amplify race window)
PENDING_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
for i in $(seq 1 100); do
    echo '{"ts":"2026-04-28T05:30:00Z","repo_root":"/test/repo","event_uuid":"uuid-'"${i}"'","action_id":"200","decision_class":"A","skill":"bootstrapping-repo","summary":"approval=auto outcome=success payload={}","mode":"bootstrap-pending","status":"pending","retry_count":0,"pending_since":"'"${PENDING_TS}"'"}' >> "${JSONL}"
done

touch "${HOME}/.board-superpowers/audit-pending.sentinel"

# Three concurrent flushes
bash "${ROOT}/scripts/audit-flush-pending.sh" &
PID1=$!
bash "${ROOT}/scripts/audit-flush-pending.sh" &
PID2=$!
bash "${ROOT}/scripts/audit-flush-pending.sh" &
PID3=$!
wait "${PID1}" "${PID2}" "${PID3}" 2>/dev/null || true

# Assert 1: DB has 100 rows (UNIQUE prevents dup INSERT; flock prevents jsonl rewrite race)
DBCOUNT=$(sqlite3 "${DB}" 'SELECT COUNT(*) FROM audit_log')
[ "${DBCOUNT}" = 100 ] || { echo "FAIL: DB count = ${DBCOUNT}, expected 100"; exit 1; }

# Assert 2: jsonl has 100 rows total (no row drift from rewrite race)
TOTAL=$(grep -c '"action_id":' "${JSONL}")
[ "${TOTAL}" = 100 ] || { echo "FAIL: jsonl total = ${TOTAL}, expected 100"; exit 1; }

# Assert 3: all 100 transitioned to status=processed (no half-state)
PROCESSED=$( { grep -c '"status": "processed"' "${JSONL}" 2>/dev/null || true; } | head -1)
[ "${PROCESSED}" = 100 ] || { echo "FAIL: processed = ${PROCESSED}, expected 100"; exit 1; }

# Assert 4: zero pending
PENDING=$( { grep -c '"status": "pending"' "${JSONL}" 2>/dev/null || true; } | head -1)
[ "${PENDING}" = 0 ] || { echo "FAIL: pending = ${PENDING}, expected 0"; exit 1; }

echo "PASS"
