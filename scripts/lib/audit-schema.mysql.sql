-- board-superpowers audit log schema (MySQL dialect).
-- 9 columns (8 core + event_uuid for idempotent replay), literally aligned
-- with postgres + sqlite siblings.

-- Use VARCHAR + CHECK (not ENUM) for actor_role / outcome /
-- approval_stage so the constraint is identical across postgres /
-- mysql / sqlite. MySQL 8.0.16+ enforces CHECK; on older mysql with
-- non-strict sql_mode, ENUM would silently coerce invalid values to ''
-- — VARCHAR + CHECK avoids that quiet-corruption mode.
--
-- event_uuid declared inline as UNIQUE KEY (not a separate
-- CREATE UNIQUE INDEX statement) so the whole schema stays
-- idempotent under CREATE TABLE IF NOT EXISTS — re-running on a
-- fresh-init host does not raise "duplicate key name" errors.
-- MySQL InnoDB treats NULLs as distinct in UNIQUE indexes, so
-- multiple NULL event_uuid rows coexist (matches sqlite + postgres).
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
    event_uuid      VARCHAR(36) NULL,
    UNIQUE KEY audit_event_uuid_uniq (event_uuid),
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

-- v2 schema baseline (fresh init); existing v1 DBs migrate via scripts/migrations/audit-v1-to-v2.sh (Task 4b).
-- migrated_at is passed explicitly so the INSERT works even when a user
-- has dropped the column-side DEFAULT (#43 followup-2 robustness).
INSERT INTO audit_schema_meta (id, version, migrated_at) VALUES (1, 2, CURRENT_TIMESTAMP(3))
    ON DUPLICATE KEY UPDATE version = 2, migrated_at = CURRENT_TIMESTAMP(3);
