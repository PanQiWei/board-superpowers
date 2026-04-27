# Degradation mode field — when the audit DB is unreachable

The audit log writes to a BYO RDBMS configured by the architect. When
the DB is unreachable (or venv to talk to it is unavailable, or the
architect chose to skip configuration), the script writes a JSON line
to a host-local file at
`~/.board-superpowers/repos/<normalized>/audit-local.jsonl` instead.
Each jsonl entry carries a `mode` field identifying why the degradation
happened.

## Current mode field values

These are the values that `audit-log-write.sh` writes for new entries.

| Value | Trigger |
|-------|---------|
| `no-db` | The architect picked "skip" at bootstrap step 2e; no audit_db_url is configured. This is a steady-state architect choice, not a transient failure. |
| `degraded-db-unavailable` | audit_db_url is configured but the DB rejected the connection (network, auth, DDL not applied). Transient — next successful write goes to DB. |
| `degraded-uv-missing` | The host doesn't have uv installed. Recovery: run bootstrap-host.sh. |
| `degraded-venv-create-failed` | uv is installed but `uv sync` failed (offline / proxy / lock conflict / disk full). Recovery: investigate uv error and re-run. |

## Legacy mode field value

This value appears in jsonl files written by older plugin versions.
Readers MUST handle it for forward-compat; writers MUST NOT emit new
entries with this value.

| Value | Origin |
|-------|--------|
| `v1-minimum-degraded` | Written by older plugin versions where every audit row landed in jsonl regardless of DB configuration. Readers encounter this on hosts upgraded from those versions. |

## Reader convention

Tools that read the jsonl file MUST handle both legacy and current
modes. The recommended pattern:

```python
if entry.get('mode') == 'v1-minimum-degraded':
    # legacy entry: not classified by failure cause
    ...
elif entry.get('mode') in ('no-db', 'degraded-db-unavailable',
                           'degraded-uv-missing', 'degraded-venv-create-failed'):
    # current: failure-cause classified
    ...
```

## SPOT

Only `bsp_audit_local_write` in `scripts/lib/common.sh` writes the mode
field. SKILL bodies, audit-log-write.sh, audit-init.sh, and other
callers do NOT duplicate the value list — they pass the mode string
through to the helper.
