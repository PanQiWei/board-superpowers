#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT

# Prepare a v1-shape SQLite DB (no event_uuid column, audit_schema_meta.version=1)
DB="${TMPDIR}/v1.db"
sqlite3 "${DB}" <<'SQL'
CREATE TABLE audit_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,
    project TEXT NOT NULL,
    session_id TEXT NOT NULL,
    actor_role TEXT NOT NULL,
    action_id INTEGER NOT NULL,
    payload TEXT NOT NULL,
    outcome TEXT NOT NULL,
    approval_stage TEXT NOT NULL
);
CREATE TABLE audit_schema_meta (
    id INTEGER PRIMARY KEY CHECK (id=1),
    version INTEGER NOT NULL,
    migrated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);
INSERT INTO audit_schema_meta (id, version) VALUES (1, 1);
INSERT INTO audit_log (timestamp,project,session_id,actor_role,action_id,payload,outcome,approval_stage)
    VALUES ('2026-01-01','p/1','s1','consumer',200,'{}','success','auto');
SQL

export BOARD_SP_AUDIT_DB_URL="sqlite:////${DB}"

# Run migration once
bash "${ROOT}/scripts/migrations/audit-v1-to-v2.sh"

# Assert 1: version is now 2
[ "$(sqlite3 "${DB}" 'SELECT version FROM audit_schema_meta WHERE id=1')" = 2 ] \
    || { echo "FAIL: version not 2 after migration"; exit 1; }

# Assert 2: event_uuid column exists
sqlite3 "${DB}" 'PRAGMA table_info(audit_log)' | grep -q event_uuid \
    || { echo "FAIL: event_uuid column missing after migration"; exit 1; }

# Assert 3: UNIQUE index exists
sqlite3 "${DB}" "SELECT name FROM sqlite_master WHERE type='index' AND name='audit_event_uuid_uniq'" \
    | grep -q audit_event_uuid_uniq || { echo "FAIL: UNIQUE index missing after migration"; exit 1; }

# Assert 4: idempotency — re-running migration is a no-op (version stays at 2, no errors)
bash "${ROOT}/scripts/migrations/audit-v1-to-v2.sh"
[ "$(sqlite3 "${DB}" 'SELECT version FROM audit_schema_meta WHERE id=1')" = 2 ] \
    || { echo "FAIL: idempotency broken — version drifted on second run"; exit 1; }

# Assert 5: pre-existing rows have NULL event_uuid (allowed by UNIQUE on NULL)
NULLS=$(sqlite3 "${DB}" 'SELECT COUNT(*) FROM audit_log WHERE event_uuid IS NULL')
[ "${NULLS}" = 1 ] || { echo "FAIL: expected 1 NULL row (the v1 leftover), got ${NULLS}"; exit 1; }

# Assert 6: new INSERT with event_uuid still works + UNIQUE enforced
sqlite3 "${DB}" "INSERT INTO audit_log (timestamp,project,session_id,actor_role,action_id,payload,outcome,approval_stage,event_uuid) VALUES ('2026-01-02','p/1','s2','consumer',201,'{}','success','auto','test-uuid-1')"
RC=0
sqlite3 "${DB}" "INSERT INTO audit_log (timestamp,project,session_id,actor_role,action_id,payload,outcome,approval_stage,event_uuid) VALUES ('2026-01-03','p/1','s3','consumer',202,'{}','success','auto','test-uuid-1')" 2>/dev/null || RC=$?
[ "${RC}" != 0 ] || { echo "FAIL: duplicate event_uuid INSERT should fail post-migration"; exit 1; }

# --- Assert 7 — robustness against schema_meta without DEFAULT (#43 followup-2)
# The migration must not partial-apply (column added, schema_meta
# unchanged) when audit_schema_meta.migrated_at lacks a DEFAULT clause.
# Build a fresh v1-shape DB with NO DEFAULT on migrated_at.
DB2="${TMPDIR}/v1-no-default.db"
sqlite3 "${DB2}" <<'SQL'
CREATE TABLE audit_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,
    project TEXT NOT NULL,
    session_id TEXT NOT NULL,
    actor_role TEXT NOT NULL,
    action_id INTEGER NOT NULL,
    payload TEXT NOT NULL,
    outcome TEXT NOT NULL,
    approval_stage TEXT NOT NULL
);
CREATE TABLE audit_schema_meta (
    id INTEGER PRIMARY KEY CHECK (id=1),
    version INTEGER NOT NULL,
    migrated_at TEXT NOT NULL
);
INSERT INTO audit_schema_meta (id, version, migrated_at) VALUES (1, 1, '2026-01-01T00:00:00Z');
SQL

export BOARD_SP_AUDIT_DB_URL="sqlite:////${DB2}"
bash "${ROOT}/scripts/migrations/audit-v1-to-v2.sh" \
    || { echo "FAIL: migration must not depend on schema-side DEFAULT for migrated_at"; exit 1; }
[ "$(sqlite3 "${DB2}" 'SELECT version FROM audit_schema_meta WHERE id=1')" = 2 ] \
    || { echo "FAIL: schema_meta did not advance to v2 (no-DEFAULT regression)"; exit 1; }
sqlite3 "${DB2}" 'PRAGMA table_info(audit_log)' | grep -q event_uuid \
    || { echo "FAIL: event_uuid column missing post-migration in no-DEFAULT mode"; exit 1; }

echo "PASS"
