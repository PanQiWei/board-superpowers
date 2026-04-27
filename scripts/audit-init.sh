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

# Step 4: dispatch DDL apply.
SCHEMA_DIR="${SCRIPT_DIR}/lib"
case "${SCHEME}" in
    sqlite|sqlite3)
        DB_PATH="$(printf '%s' "${AUDIT_DB_URL}" | sed -E 's|^sqlite[3]?://||; s|^/||')"
        # SQLAlchemy 4-slash convention → leading / preserved by stripping only 3.
        # Re-add leading / for absolute paths.
        case "${AUDIT_DB_URL}" in
            sqlite:////*|sqlite3:////*) DB_PATH="/$(printf '%s' "${AUDIT_DB_URL}" | sed -E 's|^sqlite[3]?:////||')" ;;
        esac
        mkdir -p "$(dirname "${DB_PATH}")"
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

# Step 5: verify audit_schema_meta.version=1.
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

if [ "${VER}" != "1" ]; then
    bsp_die "audit_schema_meta.version=${VER}, expected 1"
fi

bsp_log "audit DB initialized at ${AUDIT_DB_URL} (schema v1)"
exit 0
