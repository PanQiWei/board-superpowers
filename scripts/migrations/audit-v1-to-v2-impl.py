#!/usr/bin/env python3
"""Canonical migration impl — v1 → v2: add event_uuid column + UNIQUE index.

Idempotent: checks current schema_version + column/index existence before mutating.

Reads:
  $BSP_AUDIT_DB_URL — DSN (sqlite://, postgresql://, mysql://, mysql+pymysql://)

Exit codes:
  0 — migration applied (or already at v2)
  1 — migration failed
  2 — unsupported scheme (caller should pre-check)

Robustness note (#43 followup-2): all three dialect branches pass an
explicit migrated_at value when bumping audit_schema_meta to version 2,
rather than relying on the column's schema-side DEFAULT. A user (or a
future schema rev) might drop the DEFAULT clause; the migration must
not partial-apply (column added, schema_meta unchanged) just because
NOT NULL fired during the version bump.
"""
import os
import sys
from datetime import datetime, timezone
from urllib.parse import urlparse

url_str = os.environ['BSP_AUDIT_DB_URL']
url = urlparse(url_str)
scheme = url.scheme
NOW_ISO = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

if scheme in ('sqlite', 'sqlite3'):
    import sqlite3
    db_path = url_str.replace(scheme + '://', '', 1)
    if not db_path.startswith('/'):
        db_path = '/' + db_path.lstrip('/')
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    # Check version
    cur.execute("SELECT version FROM audit_schema_meta WHERE id=1")
    row = cur.fetchone()
    version = int(row[0]) if row else 0

    if version >= 2:
        print("audit-v1-to-v2: SQLite already at v{}, no-op".format(version))
        conn.close()
        sys.exit(0)

    # Check column existence (idempotency for partial migration)
    cur.execute("PRAGMA table_info(audit_log)")
    cols = [r[1] for r in cur.fetchall()]
    if 'event_uuid' not in cols:
        cur.execute("ALTER TABLE audit_log ADD COLUMN event_uuid TEXT")

    # Check index existence
    cur.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='audit_event_uuid_uniq'")
    if not cur.fetchone():
        cur.execute("CREATE UNIQUE INDEX audit_event_uuid_uniq ON audit_log(event_uuid)")

    cur.execute(
        "INSERT OR REPLACE INTO audit_schema_meta (id, version, migrated_at) VALUES (1, 2, ?)",
        (NOW_ISO,),
    )
    conn.commit()
    conn.close()
    print("audit-v1-to-v2: SQLite migration applied")

elif scheme in ('postgresql', 'postgres'):
    try:
        import psycopg2
    except ImportError:
        sys.stderr.write("audit-v1-to-v2: psycopg2 not available; install via per-repo venv\n")
        sys.exit(1)
    conn = psycopg2.connect(url_str)
    with conn.cursor() as cur:
        cur.execute("SELECT version FROM audit_schema_meta WHERE id=1")
        row = cur.fetchone()
        version = int(row[0]) if row else 0
        if version >= 2:
            print("audit-v1-to-v2: PostgreSQL already at v{}, no-op".format(version))
            conn.close()
            sys.exit(0)

        # PG supports IF NOT EXISTS on both ALTER ADD COLUMN and CREATE UNIQUE INDEX
        cur.execute("ALTER TABLE audit_log ADD COLUMN IF NOT EXISTS event_uuid TEXT")
        cur.execute("CREATE UNIQUE INDEX IF NOT EXISTS audit_event_uuid_uniq ON audit_log(event_uuid)")
        cur.execute(
            "INSERT INTO audit_schema_meta (id, version, migrated_at) "
            "VALUES (1, 2, CURRENT_TIMESTAMP) "
            "ON CONFLICT (id) DO UPDATE SET version=2, migrated_at=CURRENT_TIMESTAMP"
        )
    conn.commit()
    conn.close()
    print("audit-v1-to-v2: PostgreSQL migration applied")

elif scheme in ('mysql', 'mysql+pymysql'):
    import pymysql
    canonical = url_str.replace('mysql+pymysql://', 'mysql://')
    u = urlparse(canonical)
    conn = pymysql.connect(
        host=u.hostname or 'localhost',
        port=u.port or 3306,
        user=u.username,
        password=u.password,
        database=u.path.lstrip('/'),
    )
    with conn.cursor() as cur:
        cur.execute("SELECT version FROM audit_schema_meta WHERE id=1")
        row = cur.fetchone()
        version = int(row[0]) if row else 0
        if version >= 2:
            print("audit-v1-to-v2: MySQL already at v{}, no-op".format(version))
            conn.close()
            sys.exit(0)

        # MySQL: no IF NOT EXISTS on ALTER ADD COLUMN or CREATE INDEX → check via information_schema
        cur.execute("""
            SELECT COUNT(*) FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='audit_log'
              AND COLUMN_NAME='event_uuid'
        """)
        col_exists = cur.fetchone()[0] > 0
        if not col_exists:
            cur.execute("ALTER TABLE audit_log ADD COLUMN event_uuid VARCHAR(36) NULL")

        cur.execute("""
            SELECT COUNT(*) FROM information_schema.STATISTICS
            WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='audit_log'
              AND INDEX_NAME='audit_event_uuid_uniq'
        """)
        idx_exists = cur.fetchone()[0] > 0
        if not idx_exists:
            cur.execute("CREATE UNIQUE INDEX audit_event_uuid_uniq ON audit_log(event_uuid)")

        cur.execute(
            "INSERT INTO audit_schema_meta (id, version, migrated_at) "
            "VALUES (1, 2, CURRENT_TIMESTAMP(3)) "
            "ON DUPLICATE KEY UPDATE version=2, migrated_at=CURRENT_TIMESTAMP(3)"
        )
    conn.commit()
    conn.close()
    print("audit-v1-to-v2: MySQL migration applied")

else:
    sys.stderr.write("audit-v1-to-v2: unsupported scheme: {}\n".format(scheme))
    sys.exit(2)
