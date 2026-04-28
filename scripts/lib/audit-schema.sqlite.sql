-- board-superpowers audit log schema (SQLite dialect).
-- 9 columns (8 core + event_uuid for idempotent replay), literally aligned
-- with postgres + mysql siblings.
-- payload uses TEXT (JSON-as-string) to avoid JSON1 extension dep.

CREATE TABLE IF NOT EXISTS audit_log (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp       TEXT NOT NULL,
    project         TEXT NOT NULL,
    session_id      TEXT NOT NULL,
    actor_role      TEXT NOT NULL CHECK (actor_role IN ('producer','consumer')),
    action_id       INTEGER NOT NULL,
    payload         TEXT NOT NULL,
    outcome         TEXT NOT NULL CHECK (outcome IN ('success','failure')),
    approval_stage  TEXT NOT NULL CHECK (approval_stage IN ('auto','propose','approved','rejected')),
    event_uuid      TEXT
);

-- Idempotent replay UNIQUE — per AC4 design.md §3.4.4
-- Multiple NULL event_uuid rows allowed (SQLite default for UNIQUE on NULL).
CREATE UNIQUE INDEX IF NOT EXISTS audit_event_uuid_uniq ON audit_log(event_uuid);

CREATE INDEX IF NOT EXISTS audit_project_timestamp_idx ON audit_log(project, timestamp DESC);
CREATE INDEX IF NOT EXISTS audit_session_idx           ON audit_log(session_id);
CREATE INDEX IF NOT EXISTS audit_action_id_idx         ON audit_log(action_id);
CREATE INDEX IF NOT EXISTS audit_approval_stage_idx    ON audit_log(approval_stage);

-- Singleton table: only ever has one row, identified by id=1.
-- The id PK + CHECK pin lets INSERT OR REPLACE actually no-op on re-init.
CREATE TABLE IF NOT EXISTS audit_schema_meta (
    id          INTEGER PRIMARY KEY CHECK (id = 1),
    version     INTEGER NOT NULL,
    migrated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- v2 schema baseline (fresh init); existing v1 DBs migrate via scripts/migrations/audit-v1-to-v2.sh (Task 4b).
-- migrated_at is passed explicitly so the INSERT works even when a user
-- has dropped the column-side DEFAULT (#43 followup-2 robustness).
INSERT OR REPLACE INTO audit_schema_meta (id, version, migrated_at)
    VALUES (1, 2, strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
