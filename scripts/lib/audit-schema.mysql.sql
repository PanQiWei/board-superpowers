-- board-superpowers audit log schema (MySQL dialect).
-- 8 columns, literally aligned with postgres + sqlite siblings.

-- Use VARCHAR + CHECK (not ENUM) for actor_role / outcome /
-- approval_stage so the constraint is identical across postgres /
-- mysql / sqlite. MySQL 8.0.16+ enforces CHECK; on older mysql with
-- non-strict sql_mode, ENUM would silently coerce invalid values to ''
-- — VARCHAR + CHECK avoids that quiet-corruption mode.
CREATE TABLE IF NOT EXISTS audit_log (
    id              BIGINT AUTO_INCREMENT PRIMARY KEY,
    timestamp       DATETIME(3) NOT NULL,
    project         VARCHAR(255) NOT NULL,
    session_id      VARCHAR(64) NOT NULL,
    actor_role      VARCHAR(16) NOT NULL CHECK (actor_role IN ('producer','consumer')),
    action_id       SMALLINT NOT NULL,
    payload         JSON NOT NULL,
    outcome         VARCHAR(16) NOT NULL CHECK (outcome IN ('success','failure')),
    approval_stage  VARCHAR(16) NOT NULL CHECK (approval_stage IN ('auto','propose','approved','rejected')),
    INDEX audit_project_timestamp_idx (project, timestamp DESC),
    INDEX audit_session_idx (session_id),
    INDEX audit_action_id_idx (action_id),
    INDEX audit_approval_stage_idx (approval_stage)
);

-- Singleton table: only ever has one row, identified by id=1.
CREATE TABLE IF NOT EXISTS audit_schema_meta (
    id          INTEGER PRIMARY KEY CHECK (id = 1),
    version     INTEGER NOT NULL,
    migrated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
);

INSERT INTO audit_schema_meta (id, version) VALUES (1, 1)
    ON DUPLICATE KEY UPDATE id=id;
