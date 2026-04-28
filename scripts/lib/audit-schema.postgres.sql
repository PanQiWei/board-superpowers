-- board-superpowers audit log schema (Postgres dialect).
-- 9 columns (8 core + event_uuid for idempotent replay), literally aligned
-- with mysql + sqlite siblings.
-- Per docs/architecture/0005-contracts/06-audit-log-schema.md.

CREATE TABLE IF NOT EXISTS audit_log (
    id              BIGSERIAL PRIMARY KEY,
    timestamp       TIMESTAMPTZ NOT NULL,
    project         TEXT NOT NULL,
    session_id      TEXT NOT NULL,
    actor_role      TEXT NOT NULL CHECK (actor_role IN ('producer','consumer')),
    action_id       SMALLINT NOT NULL,
    payload         JSONB NOT NULL,
    outcome         TEXT NOT NULL CHECK (outcome IN ('success','failure')),
    approval_stage  TEXT NOT NULL CHECK (approval_stage IN ('auto','propose','approved','rejected')),
    event_uuid      TEXT
);

-- Idempotent replay UNIQUE — per AC4 design.md §3.4.4
-- Postgres treats NULLs as distinct in UNIQUE indexes by default,
-- so multiple NULL event_uuid rows coexist (matches sqlite behavior).
CREATE UNIQUE INDEX IF NOT EXISTS audit_event_uuid_uniq ON audit_log(event_uuid);

CREATE INDEX IF NOT EXISTS audit_project_timestamp_idx ON audit_log(project, timestamp DESC);
CREATE INDEX IF NOT EXISTS audit_session_idx           ON audit_log(session_id);
CREATE INDEX IF NOT EXISTS audit_action_id_idx         ON audit_log(action_id);
CREATE INDEX IF NOT EXISTS audit_approval_stage_idx    ON audit_log(approval_stage);

-- Singleton table: only ever has one row, identified by id=1.
-- The id PK + CHECK pin lets ON CONFLICT actually no-op on re-init.
CREATE TABLE IF NOT EXISTS audit_schema_meta (
    id          INTEGER PRIMARY KEY CHECK (id = 1),
    version     INTEGER NOT NULL,
    migrated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- v2 schema baseline (fresh init); existing v1 DBs migrate via scripts/migrations/audit-v1-to-v2.sh (Task 4b).
-- migrated_at is passed explicitly so the INSERT works even when a user
-- has dropped the column-side DEFAULT (#43 followup-2 robustness).
INSERT INTO audit_schema_meta (id, version, migrated_at) VALUES (1, 2, CURRENT_TIMESTAMP)
    ON CONFLICT (id) DO UPDATE SET version = 2, migrated_at = CURRENT_TIMESTAMP;
