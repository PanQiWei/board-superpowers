# Audit log schema — 8 columns

The audit_log table (in postgres / mysql / sqlite) has 8 columns. Every
audit row is one INSERT.

## Columns

| Column | Type (postgres / mysql / sqlite) | Required | Notes |
|--------|----------------------------------|----------|-------|
| `id` | BIGSERIAL / BIGINT AUTO_INCREMENT / INTEGER PK AUTOINCREMENT | yes (auto) | Surrogate primary key. |
| `timestamp` | TIMESTAMPTZ / DATETIME(3) / TEXT (ISO8601 UTC) | yes | When the row was written; UTC. |
| `project` | TEXT / VARCHAR(255) / TEXT | yes | `OWNER/NUMBER` form per the BoardAdapter. |
| `session_id` | TEXT / VARCHAR(64) / TEXT | yes | The Claude Code or Codex session id. |
| `actor_role` | CHECK / ENUM ('producer','consumer') | yes | Lowercase. |
| `action_id` | SMALLINT / SMALLINT / INTEGER | yes | Matrix row from classifying-actions. |
| `payload` | JSONB / JSON / TEXT (JSON-as-string) | yes | Per-action_id shape; see db-write-conventions.md. |
| `outcome` | CHECK / ENUM ('success','failure') | yes | Did the action's effect land? |
| `approval_stage` | CHECK / ENUM ('auto','propose','approved','rejected') | yes | Where the action sits in the approval lifecycle. |

## Indices

The DDL ships 4 starter indices:

```sql
CREATE INDEX audit_project_timestamp_idx ON audit_log(project, timestamp DESC);
CREATE INDEX audit_session_idx           ON audit_log(session_id);
CREATE INDEX audit_action_id_idx         ON audit_log(action_id);
CREATE INDEX audit_approval_stage_idx    ON audit_log(approval_stage);
```

Architects can add more indices; the plugin doesn't manage them past
the starter set.

## Schema version sentinel

A sibling table `audit_schema_meta` carries a `version` integer; the
current sentinel version is `1`. Future schema migrations bump this
lazily on first write per session.

## Append-only

The contract is append-only: no UPDATE, no DELETE. Once written, an
audit row is immutable.
