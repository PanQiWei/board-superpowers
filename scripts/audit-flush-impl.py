#!/usr/bin/env python3
"""Outbox flush impl - reads jsonl, INSERTs to per-row DSN, transitions status.

Reads:
  $BSP_JSONL - path to one audit-local.jsonl

Per pending row:
  1. Resolve audit_db_url (env BOARD_SP_AUDIT_DB_URL > host credentials.yml)
  2. Cross-driver INSERT with UNIQUE event_uuid (SQLite OR IGNORE / PG ON
     CONFLICT DO NOTHING / MySQL ON DUPLICATE KEY UPDATE event_uuid=event_uuid)
  3. On success: status=pending -> status=processed (row preserved)
  4. On INSERT failure: retry_count++; if >=5 -> mode=audit-dead-letter, status=failed
  5. TTL: pending_since > 24h ago -> mode=audit-dead-letter, status=failed

Writes back jsonl in-place (atomic rename).

Exit codes:
  0 - flush complete (all pending succeeded or transitioned)
  1 - corrupt jsonl rows detected (preserved as raw text + dead-letter mode)
  2 - partial INSERT failure (some rows still pending or transitioned to dead-letter)
"""
import json
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlparse

JSONL = Path(os.environ['BSP_JSONL'])
RETRY_MAX = 5
TTL_HOURS = 24


def resolve_audit_db_url(_repo_root):
    """Resolve DSN; per-row repo_root currently informational
    (host-shared DSN per ADR-0006 §5)."""
    env_url = os.environ.get('BOARD_SP_AUDIT_DB_URL')
    if env_url:
        return env_url
    creds = Path.home() / '.board-superpowers' / 'credentials.yml'
    if creds.is_file():
        for line in creds.read_text().splitlines():
            stripped = line.strip()
            if stripped.startswith('#'):
                continue
            if stripped.startswith('audit_db_url'):
                _, _, val = stripped.partition(':')
                return val.strip().strip('"').strip("'")
    return None


def insert_row(audit_db_url, row):
    """Cross-driver INSERT with UNIQUE event_uuid handling.
    Returns True on success/duplicate."""
    url = urlparse(audit_db_url)
    scheme = url.scheme

    summary_str = row.get('summary', '')
    payload = ''
    if 'payload=' in summary_str:
        payload = summary_str.split('payload=', 1)[1]

    actor_role = 'producer'
    if row.get('skill', '') == 'consuming-card':
        actor_role = 'consumer'

    outcome = 'success' if 'outcome=success' in summary_str else 'failure'
    if 'approval=propose' in summary_str:
        approval = 'propose'
    elif 'approval=approved' in summary_str:
        approval = 'approved'
    elif 'approval=rejected' in summary_str:
        approval = 'rejected'
    else:
        approval = 'auto'

    try:
        action_id = int(row.get('action_id'))
    except (TypeError, ValueError):
        return False

    values = (
        row.get('ts'),
        row.get('project', 'unknown/0'),
        row.get('session_id', 'flush-' + str(row.get('event_uuid', ''))[:8]),
        actor_role,
        action_id,
        payload or '{}',
        outcome,
        approval,
        row.get('event_uuid'),
    )

    try:
        if scheme in ('sqlite', 'sqlite3'):
            import sqlite3
            db_path = audit_db_url.replace(scheme + '://', '', 1)
            if not db_path.startswith('/'):
                db_path = '/' + db_path.lstrip('/')
            conn = sqlite3.connect(db_path)
            conn.execute(
                "INSERT OR IGNORE INTO audit_log "
                "(timestamp, project, session_id, actor_role, action_id, "
                "payload, outcome, approval_stage, event_uuid) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                values,
            )
            conn.commit()
            conn.close()
            return True
        if scheme in ('postgresql', 'postgres'):
            import psycopg2
            conn = psycopg2.connect(audit_db_url)
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO audit_log "
                    "(timestamp, project, session_id, actor_role, action_id, "
                    "payload, outcome, approval_stage, event_uuid) "
                    "VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s) "
                    "ON CONFLICT (event_uuid) DO NOTHING",
                    values,
                )
            conn.commit()
            conn.close()
            return True
        if scheme in ('mysql', 'mysql+pymysql'):
            import pymysql
            canonical = audit_db_url.replace('mysql+pymysql://', 'mysql://')
            u = urlparse(canonical)
            conn = pymysql.connect(
                host=u.hostname, port=u.port or 3306,
                user=u.username, password=u.password,
                database=u.path.lstrip('/'),
            )
            with conn.cursor() as cur:
                # ON DUPLICATE KEY UPDATE event_uuid=event_uuid (Codex blocker fix)
                # vs INSERT IGNORE which swallows truncation/JSON errors
                cur.execute(
                    "INSERT INTO audit_log "
                    "(timestamp, project, session_id, actor_role, action_id, "
                    "payload, outcome, approval_stage, event_uuid) "
                    "VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s) "
                    "ON DUPLICATE KEY UPDATE event_uuid=event_uuid",
                    values,
                )
            conn.commit()
            conn.close()
            return True
    except Exception as e:
        sys.stderr.write(
            "audit-flush-impl: insert failed for {}: {}\n".format(
                row.get('event_uuid'), e
            )
        )
        return False
    return False


def main():
    rows = []
    raw_lines = []
    corrupt_count = 0
    with open(JSONL) as f:
        for raw in f:
            stripped = raw.strip()
            if not stripped:
                rows.append(None)
                raw_lines.append(raw)
                continue
            try:
                rows.append(json.loads(stripped))
                raw_lines.append(None)
            except json.JSONDecodeError:
                rows.append({
                    "_corrupt_raw": stripped,
                    "mode": "audit-dead-letter",
                    "status": "failed",
                })
                raw_lines.append(None)
                corrupt_count += 1

    now = datetime.now(timezone.utc)
    insert_failures = 0

    for row in rows:
        if row is None:
            continue
        if "_corrupt_raw" in row:
            continue
        if row.get('status') != 'pending':
            continue

        # TTL check first
        ts_str = row.get('pending_since', '')
        try:
            since = datetime.fromisoformat(ts_str.rstrip('Z'))
            if since.tzinfo is None:
                since = since.replace(tzinfo=timezone.utc)
            if now - since > timedelta(hours=TTL_HOURS):
                row['mode'] = 'audit-dead-letter'
                row['status'] = 'failed'
                insert_failures += 1
                continue
        except (ValueError, AttributeError):
            pass

        repo_root = row.get('repo_root', '')
        audit_db_url = resolve_audit_db_url(repo_root)
        if not audit_db_url:
            sys.stderr.write(
                "audit-flush-impl: no audit_db_url for {}; skipping\n".format(
                    row.get('event_uuid')
                )
            )
            insert_failures += 1
            continue

        if insert_row(audit_db_url, row):
            row['status'] = 'processed'
        else:
            row['retry_count'] = row.get('retry_count', 0) + 1
            if row['retry_count'] >= RETRY_MAX:
                row['mode'] = 'audit-dead-letter'
                row['status'] = 'failed'
            insert_failures += 1

    # Atomic rewrite
    tmp = JSONL.with_suffix('.jsonl.tmp')
    with open(tmp, 'w') as f:
        for i, row in enumerate(rows):
            if row is None:
                f.write(raw_lines[i])
                continue
            if "_corrupt_raw" in row:
                f.write(row["_corrupt_raw"] + '\n')
            else:
                f.write(json.dumps(row) + '\n')
    tmp.replace(JSONL)

    if corrupt_count > 0:
        sys.exit(1)
    if insert_failures > 0:
        sys.exit(2)
    sys.exit(0)


if __name__ == '__main__':
    main()
