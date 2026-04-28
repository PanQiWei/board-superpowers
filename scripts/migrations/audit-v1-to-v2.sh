#!/usr/bin/env bash
# scripts/migrations/audit-v1-to-v2.sh
# Canonical migration per docs/architecture/0005-contracts/06-audit-log-schema.md
# § "Migration model": lazy-on-read; invoked by audit-init.sh when
# audit_schema_meta.version < 2. Idempotent.
#
# Adds event_uuid column + UNIQUE index (audit_event_uuid_uniq) to audit_log.
# Bumps audit_schema_meta.version 1 → 2.
#
# Exit codes:
#   0 — migration applied (or schema already at v2)
#   1 — migration failed (transport / DDL error)
#   2 — unsupported scheme

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
# shellcheck source-path=SCRIPTDIR
. "${SCRIPT_DIR}/../lib/common.sh"

bsp_log "audit-v1-to-v2: starting"

AUDIT_DB_URL="$(bsp_resolve_audit_db_url)"
if [ -z "${AUDIT_DB_URL}" ]; then
    bsp_log "audit-v1-to-v2: no audit_db_url configured; nothing to migrate"
    exit 0
fi

REPO_ROOT="$(bsp_primary_repo_root "${PWD}" 2>/dev/null || echo "${PWD}")"
VENV_PYTHON="$(bsp_ensure_venv "${REPO_ROOT}")" || bsp_die "venv unavailable for migration"

SCHEME=$(printf '%s' "${AUDIT_DB_URL}" | sed -E 's|^([a-z+]+)://.*|\1|')
case "${SCHEME}" in
    sqlite|sqlite3|postgresql|postgres|mysql|mysql+pymysql) ;;
    *) bsp_warn "audit-v1-to-v2: unsupported scheme: ${SCHEME}"; exit 2 ;;
esac

BSP_AUDIT_DB_URL="${AUDIT_DB_URL}" \
    "${VENV_PYTHON}" "${SCRIPT_DIR}/audit-v1-to-v2-impl.py"
