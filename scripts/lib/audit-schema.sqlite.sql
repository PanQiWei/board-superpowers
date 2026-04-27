-- board-superpowers audit log schema (SQLite dialect).
-- 8 columns, literally aligned with postgres + mysql siblings.
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
    approval_stage  TEXT NOT NULL CHECK (approval_stage IN ('auto','propose','approved','rejected'))
);

CREATE INDEX IF NOT EXISTS audit_project_timestamp_idx ON audit_log(project, timestamp DESC);
CREATE INDEX IF NOT EXISTS audit_session_idx           ON audit_log(session_id);
CREATE INDEX IF NOT EXISTS audit_action_id_idx         ON audit_log(action_id);
CREATE INDEX IF NOT EXISTS audit_approval_stage_idx    ON audit_log(approval_stage);

CREATE TABLE IF NOT EXISTS audit_schema_meta (
    version     INTEGER NOT NULL,
    migrated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

INSERT OR IGNORE INTO audit_schema_meta (version) VALUES (1);
