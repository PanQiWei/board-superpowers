#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT
export HOME="${TMPDIR}/fake-home"

# Prepare SQLite v2 schema DB
DB="${TMPDIR}/audit.db"
sqlite3 "${DB}" < "${ROOT}/scripts/lib/audit-schema.sqlite.sql"
export BOARD_SP_AUDIT_DB_URL="sqlite:////${DB}"

# Prepare jsonl with 9 rows status=pending (simulating bootstrap outbox)
NORMALIZED="$(echo "/test/repo" | sed 's|^/||; s|/|-|g')"
JSONL_DIR="${HOME}/.board-superpowers/repos/${NORMALIZED}"
mkdir -p "${JSONL_DIR}"
JSONL="${JSONL_DIR}/audit-local.jsonl"
PENDING_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
for i in 200 201 202 203 204 205 206 207 208; do
    cat <<JSON >> "${JSONL}"
{"ts":"2026-04-28T05:30:00Z","repo_root":"/test/repo","event_uuid":"uuid-${i}","action_id":"${i}","decision_class":"A","skill":"bootstrapping-repo","summary":"approval=auto outcome=success payload={\"test\":${i}}","mode":"bootstrap-pending","status":"pending","retry_count":0,"pending_since":"${PENDING_TS}"}
JSON
done

# Touch sentinel (simulating audit-log-write's outbox emission)
touch "${HOME}/.board-superpowers/audit-pending.sentinel"

# Run flush
bash "${ROOT}/scripts/audit-flush-pending.sh"

# Assert 1: DB has 9 rows
DBCOUNT=$(sqlite3 "${DB}" 'SELECT COUNT(*) FROM audit_log')
[ "${DBCOUNT}" = 9 ] || { echo "FAIL: DB row count = ${DBCOUNT}, expected 9"; exit 1; }

# Assert 2: jsonl rows transitioned to status=processed (NOT deleted; preserve audit log)
PROCESSED=$(grep -c '"status": "processed"' "${JSONL}")
[ "${PROCESSED}" = 9 ] || { echo "FAIL: expected 9 processed, got ${PROCESSED}"; exit 1; }

# Assert 3: zero pending rows after flush
# Use grep -c | head -1 to get a single-line count even when grep itself
# outputs "0\n" with non-zero rc on no match. `|| true` guards the pipefail.
PENDING=$( { grep -c '"status": "pending"' "${JSONL}" 2>/dev/null || true; } | head -1)
[ "${PENDING}" = 0 ] || { echo "FAIL: expected 0 pending, got ${PENDING}"; exit 1; }

# Assert 4: sentinel deleted (no pending across all jsonls)
[ ! -f "${HOME}/.board-superpowers/audit-pending.sentinel" ] || { echo "FAIL: sentinel not deleted"; exit 1; }

# Assert 5: idempotency — second run is no-op (DB still 9, jsonl still all processed)
bash "${ROOT}/scripts/audit-flush-pending.sh"
[ "$(sqlite3 "${DB}" 'SELECT COUNT(*) FROM audit_log')" = 9 ] \
    || { echo "FAIL: idempotency broken"; exit 1; }

# Assert 6: TTL — row with pending_since > 24h ago goes to audit-dead-letter
TTL_TS="$(python3 -c 'import datetime; print((datetime.datetime.utcnow() - datetime.timedelta(hours=25)).strftime("%Y-%m-%dT%H:%M:%SZ"))')"
echo '{"ts":"2026-04-27T00:00:00Z","repo_root":"/test/repo","event_uuid":"uuid-stale","action_id":"200","decision_class":"A","skill":"bootstrapping-repo","summary":"test","mode":"bootstrap-pending","status":"pending","retry_count":0,"pending_since":"'"${TTL_TS}"'"}' >> "${JSONL}"
touch "${HOME}/.board-superpowers/audit-pending.sentinel"
bash "${ROOT}/scripts/audit-flush-pending.sh" || true  # may exit 2 due to dead-letter
grep -q 'uuid-stale.*audit-dead-letter' "${JSONL}" || { echo "FAIL: stale row not transitioned to audit-dead-letter"; exit 1; }

echo "PASS"
