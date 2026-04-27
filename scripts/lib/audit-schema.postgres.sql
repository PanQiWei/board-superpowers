-- board-superpowers audit log schema (Postgres dialect).
-- 8 columns, literally aligned with mysql + sqlite siblings.
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
    approval_stage  TEXT NOT NULL CHECK (approval_stage IN ('auto','propose','approved','rejected'))
);

CREATE INDEX IF NOT EXISTS audit_project_timestamp_idx ON audit_log(project, timestamp DESC);
CREATE INDEX IF NOT EXISTS audit_session_idx           ON audit_log(session_id);
CREATE INDEX IF NOT EXISTS audit_action_id_idx         ON audit_log(action_id);
CREATE INDEX IF NOT EXISTS audit_approval_stage_idx    ON audit_log(approval_stage);

CREATE TABLE IF NOT EXISTS audit_schema_meta (
    version     INTEGER NOT NULL,
    migrated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO audit_schema_meta (version) VALUES (1)
    ON CONFLICT DO NOTHING;
