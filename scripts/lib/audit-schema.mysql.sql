-- board-superpowers audit log schema (MySQL dialect).
-- 8 columns, literally aligned with postgres + sqlite siblings.

CREATE TABLE IF NOT EXISTS audit_log (
    id              BIGINT AUTO_INCREMENT PRIMARY KEY,
    timestamp       DATETIME(3) NOT NULL,
    project         VARCHAR(255) NOT NULL,
    session_id      VARCHAR(64) NOT NULL,
    actor_role      ENUM('producer','consumer') NOT NULL,
    action_id       SMALLINT NOT NULL,
    payload         JSON NOT NULL,
    outcome         ENUM('success','failure') NOT NULL,
    approval_stage  ENUM('auto','propose','approved','rejected') NOT NULL,
    INDEX audit_project_timestamp_idx (project, timestamp DESC),
    INDEX audit_session_idx (session_id),
    INDEX audit_action_id_idx (action_id),
    INDEX audit_approval_stage_idx (approval_stage)
);

CREATE TABLE IF NOT EXISTS audit_schema_meta (
    version     INTEGER NOT NULL,
    migrated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
);

INSERT INTO audit_schema_meta (version) VALUES (1)
    ON DUPLICATE KEY UPDATE version=version;
