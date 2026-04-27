#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPREPO="$(mktemp -d)"
TMPDB="$(mktemp -d)/audit.db"
trap 'rm -rf "${TMPREPO}" "$(dirname "${TMPDB}")"' EXIT

mkdir -p "${TMPREPO}/.board-superpowers"
git -C "${TMPREPO}" init -q

export CLAUDE_PLUGIN_ROOT="${SCRIPT_DIR}"
export BOARD_SP_AUDIT_DB_URL="sqlite:///${TMPDB}"

cd "${TMPREPO}"
bash "${SCRIPT_DIR}/scripts/audit-init.sh"
rc=$?
[ $rc -eq 0 ] || { echo "FAIL: audit-init.sh exit $rc"; exit 1; }

# Verify schema applied.
sqlite_version=$(sqlite3 "${TMPDB}" "SELECT version FROM audit_schema_meta")
[ "${sqlite_version}" = "1" ] || { echo "FAIL: schema_meta.version=${sqlite_version}"; exit 1; }

# Verify table exists.
tables=$(sqlite3 "${TMPDB}" ".tables")
echo "${tables}" | grep -q audit_log || { echo "FAIL: audit_log table missing"; exit 1; }

echo "PASS"
