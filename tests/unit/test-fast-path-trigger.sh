#!/usr/bin/env bash
# tests/unit/test-fast-path-trigger.sh — AC4 trigger fast-path coverage.
#
# Verifies that the bootstrap-project.sh fast-path call to
# audit-flush-pending.sh (Task 7) correctly drains pending outbox rows
# in the same session: rows transition to processed, DB receives the
# inserts, and the wakeup sentinel is removed when nothing remains.
#
# This test exercises audit-flush-pending.sh in isolation (the same
# binary the bootstrap末尾 fast-path invokes); it is regression
# coverage that the trigger contract — "running flush after a
# bootstrap drains everything synchronously" — keeps holding as the
# flush worker evolves.

set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT
export HOME="${TMPDIR}/fake-home"
mkdir -p "${HOME}/.board-superpowers"

DB="${TMPDIR}/audit.db"
sqlite3 "${DB}" < "${ROOT}/scripts/lib/audit-schema.sqlite.sql"
export BOARD_SP_AUDIT_DB_URL="sqlite:////${DB}"

# Simulate post-bootstrap state: jsonl has pending rows + sentinel exists
NORMALIZED="$(echo "/test/repo" | sed 's|^/||; s|/|-|g')"
JSONL_DIR="${HOME}/.board-superpowers/repos/${NORMALIZED}"
mkdir -p "${JSONL_DIR}"
JSONL="${JSONL_DIR}/audit-local.jsonl"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
for i in 200 201 202; do
    echo '{"ts":"2026-04-28T05:30:00Z","repo_root":"/test/repo","event_uuid":"uuid-'"${i}"'","action_id":"'"${i}"'","decision_class":"A","skill":"bootstrapping-repo","summary":"approval=auto outcome=success payload={}","mode":"bootstrap-pending","status":"pending","retry_count":0,"pending_since":"'"${TS}"'"}' >> "${JSONL}"
done
touch "${HOME}/.board-superpowers/audit-pending.sentinel"

# Fast-path flush call (what bootstrap-project.sh末尾 does at Task 7)
bash "${ROOT}/scripts/audit-flush-pending.sh"

# Assert: 3 rows in DB
DBCOUNT="$(sqlite3 "${DB}" 'SELECT COUNT(*) FROM audit_log')"
[ "${DBCOUNT}" = 3 ] \
    || { echo "FAIL: expected 3 rows in DB, got ${DBCOUNT}"; exit 1; }

# Assert: sentinel deleted (nothing pending remains)
[ ! -f "${HOME}/.board-superpowers/audit-pending.sentinel" ] \
    || { echo "FAIL: sentinel not deleted post-fast-path"; exit 1; }

# Assert: jsonl rows transitioned status=processed
PROCESSED="$( { grep -c '"status": "processed"' "${JSONL}" 2>/dev/null || true; } | head -1)"
[ "${PROCESSED}" = 3 ] \
    || { echo "FAIL: rows not transitioned to processed (got ${PROCESSED}, expected 3)"; exit 1; }

echo "PASS"
