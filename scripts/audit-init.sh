#!/usr/bin/env bash
# scripts/audit-init.sh — one-shot DDL apply for the audit log.
#
# Called by bootstrap-project.sh step 2g + manual architect re-run.
# Idempotent (DDL IF NOT EXISTS + sentinel UPSERT).
#
# Reads BOARD_SP_AUDIT_DB_URL > ~/.board-superpowers/credentials.yml:audit_db_url.
# Dispatches DDL apply by URL scheme (6-scheme allowlist per ADR-0009).
#
# Exit codes:
#   0 — DDL applied (or schema already at current version)
#   1 — DB unreachable / DDL failed / venv create fail
#   2 — Bad arguments
#   3 — psql / mysql client unavailable on PATH (sqlite uses stdlib)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
# shellcheck source-path=SCRIPTDIR
source "${SCRIPT_DIR}/lib/common.sh"

bsp_log "audit-init.sh starting"

# Step 1: ensure venv (self-healing).
REPO_ROOT="$(bsp_primary_repo_root "${PWD}" 2>/dev/null || echo "${PWD}")"
if ! bsp_ensure_venv "${REPO_ROOT}" >/dev/null 2>&1; then
    bsp_die "venv unavailable at ${REPO_ROOT}/.board-superpowers/.venv — run bootstrap-host.sh first if uv missing"
fi
VENV_PYTHON="${REPO_ROOT}/.board-superpowers/.venv/bin/python3"

# Step 2: resolve audit_db_url.
AUDIT_DB_URL="$(bsp_resolve_audit_db_url)"
if [ -z "${AUDIT_DB_URL}" ]; then
    bsp_log "no audit_db_url configured (env or credentials.yml) — nothing to init"
    exit 0
fi

# Step 3: parse URL scheme.
SCHEME="$(printf '%s' "${AUDIT_DB_URL}" | sed -E 's|^([a-z+]+)://.*|\1|')"
case "${SCHEME}" in
    sqlite|sqlite3) :;;
    postgresql|postgres) :;;
    mysql|mysql+pymysql) :;;
    *) bsp_die "unsupported scheme: ${SCHEME} (allowlist: sqlite/sqlite3/postgresql/postgres/mysql/mysql+pymysql)" ;;
esac

# Step 4: pre-init schema-version detection. Determines whether we need
# to run lazy migrations BEFORE applying fresh-init DDL. A v1-shape DB
# (no event_uuid column) cannot accept the v2 DDL's
# `CREATE UNIQUE INDEX … ON audit_log(event_uuid)` until the column has
# been added by audit-v1-to-v2.sh. A pre-existing DB at the target
# version is detected here and migration is skipped (no-op). Fresh
# (non-existent) DBs report version 0 — fresh-init DDL handles those.
TARGET_VERSION=2

# Compute SQLite db_path early so we can stat the file (presence = pre-existing DB).
SCHEMA_DIR="${SCRIPT_DIR}/lib"
DB_PATH=""
if [ "${SCHEME}" = "sqlite" ] || [ "${SCHEME}" = "sqlite3" ]; then
    DB_PATH="$(printf '%s' "${AUDIT_DB_URL}" | sed -E 's|^sqlite[3]?://||; s|^/||')"
    case "${AUDIT_DB_URL}" in
        sqlite:////*|sqlite3:////*) DB_PATH="/$(printf '%s' "${AUDIT_DB_URL}" | sed -E 's|^sqlite[3]?:////||')" ;;
    esac
    mkdir -p "$(dirname "${DB_PATH}")"
fi

# Read the current schema version. Heredoc swallows errors and prints 0
# (treated as fresh-init below). The migrations are themselves idempotent
# so a false-zero on a target-version DB just no-ops.
SCHEMA_VERSION=$(BSP_AUDIT_DB_URL="${AUDIT_DB_URL}" "${VENV_PYTHON}" - <<'PY' 2>/dev/null || echo 0
import os
from urllib.parse import urlparse
url_str = os.environ['BSP_AUDIT_DB_URL']
url = urlparse(url_str)
scheme = url.scheme
try:
    if scheme in ('sqlite', 'sqlite3'):
        import sqlite3
        db_path = url_str.replace(scheme + '://', '', 1)
        if not db_path.startswith('/'): db_path = '/' + db_path.lstrip('/')
        if not os.path.exists(db_path):
            print(0)
        else:
            conn = sqlite3.connect(db_path)
            cur = conn.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='audit_schema_meta'")
            if cur.fetchone() is None:
                print(0)
            else:
                row = conn.execute("SELECT version FROM audit_schema_meta WHERE id=1").fetchone()
                print(int(row[0]) if row else 0)
            conn.close()
    elif scheme in ('postgresql', 'postgres'):
        import psycopg2
        conn = psycopg2.connect(url_str)
        with conn.cursor() as c:
            c.execute("""SELECT to_regclass('public.audit_schema_meta')""")
            if c.fetchone()[0] is None:
                print(0)
            else:
                c.execute("SELECT version FROM audit_schema_meta WHERE id=1")
                r = c.fetchone()
                print(int(r[0]) if r else 0)
        conn.close()
    elif scheme in ('mysql', 'mysql+pymysql'):
        import pymysql
        canonical = url_str.replace('mysql+pymysql://', 'mysql://')
        u = urlparse(canonical)
        conn = pymysql.connect(host=u.hostname, port=u.port or 3306, user=u.username, password=u.password, database=u.path.lstrip('/'))
        with conn.cursor() as c:
            c.execute("""SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='audit_schema_meta'""")
            if c.fetchone()[0] == 0:
                print(0)
            else:
                c.execute("SELECT version FROM audit_schema_meta WHERE id=1")
                r = c.fetchone()
                print(int(r[0]) if r else 0)
        conn.close()
    else:
        print(0)
except Exception:
    print(0)
PY
)
case "${SCHEMA_VERSION}" in
    ''|*[!0-9]*) SCHEMA_VERSION=0 ;;
esac

# Step 5: dispatch lazy migration FIRST when we detected a pre-existing
# DB below the target version. This brings the schema shape up so the
# fresh-init DDL in step 6 (with its v2-shape CREATE UNIQUE INDEX on
# event_uuid) can apply idempotently.
if [ "${SCHEMA_VERSION}" -gt 0 ] && [ "${SCHEMA_VERSION}" -lt "${TARGET_VERSION}" ]; then
    bsp_log "audit-init: schema v${SCHEMA_VERSION} < v${TARGET_VERSION}; dispatching migration"
    VER_FROM=${SCHEMA_VERSION}
    while [ "${VER_FROM}" -lt "${TARGET_VERSION}" ]; do
        VER_TO=$((VER_FROM + 1))
        MIGRATION="${SCRIPT_DIR}/migrations/audit-v${VER_FROM}-to-v${VER_TO}.sh"
        if [ -x "${MIGRATION}" ]; then
            bsp_log "audit-init: running ${MIGRATION}"
            bash "${MIGRATION}" || bsp_die "migration v${VER_FROM} → v${VER_TO} failed"
        fi
        VER_FROM=${VER_TO}
    done
fi

# Step 6: dispatch fresh-init DDL apply (idempotent — IF NOT EXISTS guards).
case "${SCHEME}" in
    sqlite|sqlite3)
        BSP_DB_PATH="${DB_PATH}" \
        BSP_SCHEMA_FILE="${SCHEMA_DIR}/audit-schema.sqlite.sql" \
        "${VENV_PYTHON}" - <<'PY'
import os, sqlite3
conn = sqlite3.connect(os.environ['BSP_DB_PATH'])
with open(os.environ['BSP_SCHEMA_FILE']) as f:
    conn.executescript(f.read())
conn.commit()
conn.close()
PY
        ;;
    postgresql|postgres)
        # Explicit psql client check returns exit 3 (script docstring contract);
        # bsp_require_cmd would have exited 1 instead.
        if ! command -v psql >/dev/null 2>&1; then
            bsp_warn "psql client not on PATH — install via 'brew install libpq && brew link libpq --force' on macOS, or apt-get install postgresql-client on Linux"
            exit 3
        fi
        psql "${AUDIT_DB_URL}" -f "${SCHEMA_DIR}/audit-schema.postgres.sql" >&2
        ;;
    mysql|mysql+pymysql)
        # Use venv-python pymysql for executescript-equivalent.
        # Pass values via env vars so unusual chars in DSN/path can't break
        # the Python source (heredoc is quoted to disable shell interpolation).
        BSP_AUDIT_DB_URL="${AUDIT_DB_URL}" \
        BSP_SCHEMA_FILE="${SCHEMA_DIR}/audit-schema.mysql.sql" \
        "${VENV_PYTHON}" - <<'PY'
import os
import pymysql
from urllib.parse import urlparse
url_str = os.environ['BSP_AUDIT_DB_URL'].replace('mysql+pymysql://', 'mysql://')
url = urlparse(url_str)
conn = pymysql.connect(
    host=url.hostname or 'localhost',
    port=url.port or 3306,
    user=url.username,
    password=url.password,
    database=url.path.lstrip('/'),
)
with open(os.environ['BSP_SCHEMA_FILE']) as f:
    sql = f.read()
with conn.cursor() as cur:
    for stmt in sql.split(';'):
        stmt = stmt.strip()
        if stmt:
            cur.execute(stmt)
conn.commit()
conn.close()
PY
        ;;
esac

# Step 7: verify final schema version meets target.
case "${SCHEME}" in
    sqlite|sqlite3)
        VER=$(sqlite3 "${DB_PATH}" "SELECT version FROM audit_schema_meta LIMIT 1")
        ;;
    postgresql|postgres)
        VER=$(psql "${AUDIT_DB_URL}" -tA -c "SELECT version FROM audit_schema_meta LIMIT 1")
        ;;
    mysql|mysql+pymysql)
        VER=$(BSP_AUDIT_DB_URL="${AUDIT_DB_URL}" "${VENV_PYTHON}" - <<'PY'
import os
import pymysql
from urllib.parse import urlparse
url_str = os.environ['BSP_AUDIT_DB_URL'].replace('mysql+pymysql://', 'mysql://')
url = urlparse(url_str)
conn = pymysql.connect(
    host=url.hostname,
    port=url.port or 3306,
    user=url.username,
    password=url.password,
    database=url.path.lstrip('/'),
)
with conn.cursor() as cur:
    cur.execute("SELECT version FROM audit_schema_meta LIMIT 1")
    row = cur.fetchone()
    print(row[0] if row else "")
conn.close()
PY
)
        ;;
esac

if [ "${VER}" != "${TARGET_VERSION}" ]; then
    bsp_die "audit_schema_meta.version=${VER}, expected ${TARGET_VERSION}"
fi

bsp_log "audit DB initialized at ${AUDIT_DB_URL} (schema v${TARGET_VERSION})"
exit 0
